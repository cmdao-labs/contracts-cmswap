// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20Token.sol";
import "./interfaces/v3-core/IUniswapV3Factory.sol";
import "./interfaces/v3-core/IUniswapV3Pool.sol";
import "./interfaces/v3-periphery/INonfungiblePositionManager.sol";

contract PumpFactoryLite {
    mapping(address => string) public logo;
    mapping(address => string) public desp;
    mapping(address => address) public creator;
    mapping(address => uint256) public createdTime;
    mapping(uint256 => address) public index;
    uint256 public totalIndex;
    address public feeCollector;
    uint256 public createFee;
    uint256 public constant INITIALTOKEN = 1000000000 ether;
    uint256 public initialCustomToken;
    uint160 public sqrtX96Initial0;
    uint160 public sqrtX96Initial1;
    uint256 public graduateMcap = 1 ether;
    mapping(address => bool) public isGraduate;
    IERC20 public customToken;
    IUniswapV3Factory public v3factory;
    INonfungiblePositionManager public v3posManager;
    
    constructor (
        address _customToken,
        address _v3factory,
        address _v3posManager,
        uint256 _initialCustomToken,
        uint160 _sqrtX96Initial0,
        uint160 _sqrtX96Initial1
    ) {
        customToken = IERC20(_customToken);
        v3factory = IUniswapV3Factory(_v3factory);
        v3posManager = INonfungiblePositionManager(_v3posManager);
        initialCustomToken = _initialCustomToken;
        sqrtX96Initial0 = _sqrtX96Initial0;
        sqrtX96Initial1 = _sqrtX96Initial1;
        feeCollector = msg.sender;
    }

    function setInitialCustomToken(
        uint256 _initialCustomToken,
        uint160 _sqrtX96Initial0,
        uint160 _sqrtX96Initial1
    ) external returns (bool) {
        require(msg.sender == feeCollector);
        initialCustomToken = _initialCustomToken;
        sqrtX96Initial0 = _sqrtX96Initial0;
        sqrtX96Initial1 = _sqrtX96Initial1;
        return true;
    }

    function setGraduateMcap(uint256 _graduateMcap) external returns (bool) {
        require(msg.sender == feeCollector);
        graduateMcap = _graduateMcap;
        return true;
    }

    function setCreateFee(uint256 _createFee) external returns (bool) {
        require(msg.sender == feeCollector);
        createFee = _createFee;
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
        string memory _desp
    ) external payable returns (address, address) {
        require(msg.value == createFee);
        payable(feeCollector).transfer(createFee);
        customToken.transferFrom(msg.sender, address(this), initialCustomToken);
        totalIndex++;
        ERC20Token newtoken = new ERC20Token(_name, _symbol, INITIALTOKEN);
        index[totalIndex] = address(newtoken);
        logo[address(newtoken)] = _logo;
        desp[address(newtoken)] = _desp;
        creator[address(newtoken)] = msg.sender;
        createdTime[address(newtoken)] = block.timestamp;
        (address _token0, address _token1) = address(newtoken) < address(customToken) ? (address(newtoken), address(customToken)) : (address(customToken), address(newtoken));
        (uint256 _tk0AmountToMint, uint256 _tk1AmountToMint) = address(newtoken) < address(customToken) ? (INITIALTOKEN, initialCustomToken) : (initialCustomToken, INITIALTOKEN);
        address pool = v3factory.createPool(_token0, _token1, 10000);
        if (_token0 == address(customToken)) {
            IUniswapV3Pool(pool).initialize(sqrtX96Initial0);
        } else {
            IUniswapV3Pool(pool).initialize(sqrtX96Initial1);
        }
        customToken.approve(address(v3posManager), 2**256 - 1);
        newtoken.approve(address(v3posManager), 2**256 - 1);
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: 10000,
                tickLower: -887200,
                tickUpper: 887200,
                amount0Desired: _tk0AmountToMint,
                amount1Desired: _tk1AmountToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            });
        v3posManager.mint(params);
        return (address(newtoken), pool);
    }

    function graduate(address _pool, uint256 _tokenId) external returns (bool) {
        require(!isGraduate[_pool]);
        isGraduate[_pool] = true;
        address _token0 = IUniswapV3Pool(_pool).token0();
        address _token1 = IUniswapV3Pool(_pool).token1();
        (,, address token0_, address token1_,,,,,,,,) = v3posManager.positions(_tokenId);
        require(_token0 == token0_ && _token1 == token1_);
        (uint256 _sqrtPriceX96,,,,,,) = IUniswapV3Pool(_pool).slot0();
        if (_token0 == address(customToken)) {
            require(1 / ((_sqrtPriceX96 / (2 ** 96)) ** 2) * INITIALTOKEN >= graduateMcap);
        } else {
            require((_sqrtPriceX96 / (2 ** 96)) ** 2 * INITIALTOKEN >= graduateMcap);
        }
        v3posManager.transferFrom(address(this), feeCollector, _tokenId);
        return true;
    }
}
