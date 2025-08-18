// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20FactoryETH.sol";

contract BondingCurveFeeCollectorETH {
    address public feeCollector;
    PumpFactoryNative public factoryNative;
    uint256 public graduateMcap;
    mapping(address => bool) public isGraduate;
    
    constructor (address _factoryNative) {
        factoryNative = PumpFactoryNative(_factoryNative);
        feeCollector = msg.sender;
    }

    function setInitialETH(
        uint256 _initialETH,
        uint160 _sqrtX96Initial0,
        uint160 _sqrtX96Initial1
    ) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryNative.setInitialETH(_initialETH, _sqrtX96Initial0, _sqrtX96Initial1);
        return true;
    }

    function setGraduateMcap(uint256 _graduateMcap) external returns (bool) {
        require(msg.sender == feeCollector);
        graduateMcap = _graduateMcap;
        return true;
    }

    function setCreateFee(uint256 _createFee) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryNative.setCreateFee(_createFee);
        return true;
    }

    function setFactoryFeeCollector(address _newFeeCollector) external returns (bool) {
        require(msg.sender == feeCollector);
        factoryNative.setFeeCollector(_newFeeCollector);
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
        (,, address token0_, address token1_,,,,,,,,) = factoryNative.v3posManager().positions(_tokenId);
        require(_token0 == token0_ && _token1 == token1_);
        (uint160 _sqrtPriceX96,,,,,,) = IUniswapV3Pool(_pool).slot0();
        if (_token0 == address(factoryNative.weth())) {
            require(factoryNative.INITIALTOKEN() / ((uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96)) >> 192) >= graduateMcap);
        } else {
            require(((uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96) * factoryNative.INITIALTOKEN()) >> 192) >= graduateMcap);
        }
        factoryNative.v3posManager().transferFrom(address(this), feeCollector, _tokenId);
        return true;
    }
}
