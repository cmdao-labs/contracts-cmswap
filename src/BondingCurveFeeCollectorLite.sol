// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20FactoryLite.sol";

contract BondingCurveFeeCollectorLite {
    address public feeCollector;
    PumpFactoryLite public factoryLite;
    uint256 public graduateMcap;
    mapping(address => bool) public isGraduate;
    
    constructor (address _factoryLite) {
        factoryLite = PumpFactoryLite(_factoryLite);
        feeCollector = msg.sender;
    }

    function setInitialCustomToken(
        uint256 _initialCustomToken,
        uint160 _sqrtX96Initial0,
        uint160 _sqrtX96Initial1
    ) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryLite.setInitialCustomToken(_initialCustomToken, _sqrtX96Initial0, _sqrtX96Initial1);
        return true;
    }

    function setGraduateMcap(uint256 _graduateMcap) external returns (bool) {
        require(msg.sender == feeCollector);
        graduateMcap = _graduateMcap;
        return true;
    }

    function setCreateFee(uint256 _createFee) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryLite.setCreateFee(_createFee);
        return true;
    }

    function setFactoryFeeCollector(address _newFeeCollector) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryLite.setFeeCollector(_newFeeCollector);
        return true;
    }

    function setFeeCollector(address _newFeeCollector) external returns (bool) {
        require(msg.sender == feeCollector);
        feeCollector = _newFeeCollector;
        return true;
    }

    function graduate(address _pool, uint256 _tokenId) external returns (bool) {
        require(!isGraduate[_pool]);
        isGraduate[_pool] = true;
        address _token0 = IUniswapV3Pool(_pool).token0();
        address _token1 = IUniswapV3Pool(_pool).token1();
        (,, address token0_, address token1_,,,,,,,,) = factoryLite.v3posManager().positions(_tokenId);
        require(_token0 == token0_ && _token1 == token1_);
        (uint160 _sqrtPriceX96,,,,,,) = IUniswapV3Pool(_pool).slot0();
        if (_token0 == address(factoryLite.customToken())) {
            require(factoryLite.INITIALTOKEN() / ((uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96)) >> 192) >= graduateMcap);
        } else {
            require(((uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96) * factoryLite.INITIALTOKEN()) >> 192) >= graduateMcap);
        }
        factoryLite.v3posManager().transferFrom(address(this), feeCollector, _tokenId);
        return true;
    }
}
