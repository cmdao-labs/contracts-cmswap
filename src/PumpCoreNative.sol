// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20Token.sol";
import "./interfaces/v3-core/IUniswapV3Factory.sol";
import "./interfaces/v3-core/IUniswapV3Pool.sol";
import "./interfaces/v3-periphery/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract PumpCoreNative {
    struct PumpReserve {
        uint256 native;
        uint256 token;
    }
    mapping(address => PumpReserve) public pumpReserve;
    address public feeCollector;
    uint256 public createFee;
    uint256 public pumpFee;
    uint256 public constant INITIALTOKEN = 1000000000 ether;
    uint256 public initialNative;
    uint256 public virtualAmount;
    uint256 public graduationAmount;
    mapping(address => bool) public isGraduate;
    IERC20 public wrappedNative;
    IUniswapV3Factory public v3factory;
    INonfungiblePositionManager public v3posManager;
    event Swap(
        address indexed sender,
        bool indexed isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 reserveIn, 
        uint256 reserveOut
    );
    event Creation(
        address indexed creator,
        address tokenAddr,
        string logo,
        string description,
        string link1,
        string link2,
        string link3,
        uint256 createdTime
    );
    event Graduation(
        address indexed sender,
        address tokenAddr
    );
    
    constructor (
        address _wrappedNative,
        address _v3factory,
        address _v3posManager
    ) {
        wrappedNative = IERC20(_wrappedNative);
        v3factory = IUniswapV3Factory(_v3factory);
        v3posManager = INonfungiblePositionManager(_v3posManager);
        feeCollector = msg.sender;
    }

    function setCurveState(
        uint256 _initialNative,
        uint256 _virtualAmount,
        uint256 _graduationAmount
    ) external returns (bool) {
        require(msg.sender == feeCollector);
        initialNative = _initialNative;
        virtualAmount = _virtualAmount;
        graduationAmount = _graduationAmount;
        return true;
    }

    function setFee(uint256 _createFee, uint256 _pumpFee) external returns (bool) {
        require(msg.sender == feeCollector);
        createFee = _createFee;
        pumpFee = _pumpFee;
        return true;
    }

    function setFeeCollector(address _newFeeCollector) external returns (bool) {
        require(msg.sender == feeCollector);
        feeCollector = _newFeeCollector;
        return true;
    }

    function createToken(
        string memory _name,
        string memory _symbol,
        string memory _logo,
        string memory _description,
        string memory _link1,
        string memory _link2,
        string memory _link3
    ) external payable returns (address) {
        require(msg.value == createFee + initialNative, "insufficient creation cost");

        ERC20Token newtoken = new ERC20Token(_name, _symbol, INITIALTOKEN);
        pumpReserve[address(newtoken)].native = initialNative - createFee;
        pumpReserve[address(newtoken)].token = INITIALTOKEN;

        payable(feeCollector).transfer(createFee);

        emit Creation(
            msg.sender,
            address(newtoken),
            _logo,
            _description,
            _link1,
            _link2,
            _link3,
            block.timestamp
        );
        return (address(newtoken));
    }

    function graduate(address _tokenAddr) external returns (bool) {
        require(!isGraduate[_tokenAddr], "token already graduated");
        require(pumpReserve[_tokenAddr].token / pumpReserve[_tokenAddr].native <= INITIALTOKEN / graduationAmount, "not reach graduation cap");

        isGraduate[_tokenAddr] = true;
        (address _tkn0, address _tkn1) = _tokenAddr < address(wrappedNative) ? 
            (_tokenAddr, address(wrappedNative)) :
            (address(wrappedNative), _tokenAddr);
        (uint256 _tkn0AmountToMint, uint256 _tkn1AmountToMint) = _tokenAddr < address(wrappedNative) ?
            (pumpReserve[_tokenAddr].token, pumpReserve[_tokenAddr].native) :
            (pumpReserve[_tokenAddr].native, pumpReserve[_tokenAddr].token);

        address pool = v3factory.getPool(_tkn0, _tkn1, 10000);
        if (pool == address(0)) {
            pool = v3factory.createPool(_tkn0, _tkn1, 10000);
            IUniswapV3Pool(pool).initialize(uint160(Math.sqrt((_tkn1AmountToMint * (2**192)) / _tkn0AmountToMint)));
        } else {
            (,,,,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
            if (!unlocked) {
                IUniswapV3Pool(pool).initialize(uint160(Math.sqrt((_tkn1AmountToMint * (2**192)) / _tkn0AmountToMint)));
            }
        }
        ERC20(_tokenAddr).approve(address(v3posManager), 2**256 - 1);
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: _tkn0,
                token1: _tkn1,
                fee: 10000,
                tickLower: -887200,
                tickUpper: 887200,
                amount0Desired: _tkn0AmountToMint,
                amount1Desired: _tkn1AmountToMint,
                amount0Min: (_tkn0AmountToMint * 95) / 100,
                amount1Min: (_tkn1AmountToMint * 95) / 100,
                recipient: address(0xdead),
                deadline: block.timestamp + 1 hours
            });
        v3posManager.mint{value: pumpReserve[_tokenAddr].native}(params);
        delete pumpReserve[_tokenAddr].native;
        delete pumpReserve[_tokenAddr].token;

        emit Graduation(msg.sender, _tokenAddr);
        return true;
    }

    function getAmountOut(
        uint256 _inputAmount,
        uint256 _inputReserve,
        uint256 _outputReserve
    ) public pure returns (uint256) {
        require(_inputReserve > 0 && _outputReserve > 0, "invalid reserves");
        uint256 inputAmountWithFee = _inputAmount * 99;
        uint256 numerator = _outputReserve * inputAmountWithFee;
        uint256 denominator = (_inputReserve * 100) + inputAmountWithFee;
        return numerator / denominator;
    }

    function buy(address _tokenAddr, uint256 _minToken) external payable returns (uint256) {
        require(!isGraduate[_tokenAddr], "token already graduated");

        uint256 feeAmount = (msg.value * pumpFee) / 10000;
        uint256 amountInAfterFee = msg.value - feeAmount;
        uint256 amountOut = getAmountOut(
            amountInAfterFee,
            virtualAmount + pumpReserve[_tokenAddr].native,
            pumpReserve[_tokenAddr].token
        );
        require(amountOut >= _minToken, "insufficient output amount");

        pumpReserve[_tokenAddr].native += amountInAfterFee;
        pumpReserve[_tokenAddr].token -= amountOut;

        ERC20(_tokenAddr).transfer(msg.sender, amountOut);
        payable(feeCollector).transfer(feeAmount);

        emit Swap(
            msg.sender,
            true,
            amountInAfterFee,
            amountOut,
            pumpReserve[_tokenAddr].native,
            pumpReserve[_tokenAddr].token
        );
        return amountOut;
    }

    function sell(
        address _tokenAddr,
        uint256 _tokenSold,
        uint256 _minToken
    ) external returns (uint256) {
        require(!isGraduate[_tokenAddr], "token already graduated");

        uint256 feeAmount = (_tokenSold * pumpFee) / 10000;
        uint256 amountInAfterFee = _tokenSold - feeAmount;
        uint256 amountOut = getAmountOut(
            amountInAfterFee,
            pumpReserve[_tokenAddr].token,
            virtualAmount + pumpReserve[_tokenAddr].native
        );
        require(amountOut >= _minToken, "insufficient output amount");

        pumpReserve[_tokenAddr].token += amountInAfterFee;
        pumpReserve[_tokenAddr].native -= amountOut;

        ERC20(_tokenAddr).transferFrom(msg.sender, address(this), _tokenSold);
        ERC20(_tokenAddr).transfer(feeCollector, feeAmount);
        payable(msg.sender).transfer(amountOut);

        emit Swap(
            msg.sender,
            false,
            amountInAfterFee,
            amountOut,
            pumpReserve[_tokenAddr].token,
            pumpReserve[_tokenAddr].native
        );
        return amountOut;
    }
}
