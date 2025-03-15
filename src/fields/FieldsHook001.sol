// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./interfaces/IOpenBbqFieldsV2Router.sol";

contract FieldsHook001 {
    IOpenBbqFieldsV2Router public openBbqFieldsV2Router;
    uint256 public peripheryIndexOnRouter;

    uint256 public baseHashRate; //immutable
    uint256 public bonusMultiplier = 1;
    mapping(uint256 => uint256) public hashRateForNftIndex; // boarder NFTindex hashrate
    mapping(uint256 nftIndex => mapping(uint256 nftId => uint256)) public hashRateForNftId; // specific NFTid hashrate
    mapping(uint256 => uint256) public rewardEmissionRate; // emission per point per block

    event SetBonusMultiplier(uint256 indexed oldBonusMultiplier, uint256 indexed newBonusMultiplier);
    event SetHashRateForNftIndex(uint256 indexed nftIndex, uint256 hashRate);
    event SetHashRateForNftIdRange(uint256 indexed nftIndex, uint256 indexed nftIdMin, uint256 indexed nftIdMax, uint256 hashRate);
    event SetRewardEmission(uint256 indexed rewardTokenIndex, uint256 emissionRate);
    event ClaimReward(uint256 indexed nftIndex, uint256 indexed nftId, uint256 indexed rewardTokenIndex, address claimedTo, uint256 claimedAmount);

    constructor(
        uint256 _peripheryIndexOnRouter,
        uint256 _baseHashRate,
        address _openBbqFieldsV2Router
    ) {
        peripheryIndexOnRouter = _peripheryIndexOnRouter;
        openBbqFieldsV2Router = IOpenBbqFieldsV2Router(_openBbqFieldsV2Router);
        baseHashRate = _baseHashRate;
    }

    function setBonusMultiplier(uint256 _newBonusMultiplier) external {
        require(openBbqFieldsV2Router.peripheryOwner(peripheryIndexOnRouter) == msg.sender, "not peripheryOwner");

        emit SetBonusMultiplier(bonusMultiplier, _newBonusMultiplier);

        bonusMultiplier = _newBonusMultiplier;        
    }

    function setHashRateForNftIndex(uint256 _nftIndex, uint256 _hashRate) external {
        require(openBbqFieldsV2Router.peripheryOwner(peripheryIndexOnRouter) == msg.sender, "not peripheryOwner");
        
        hashRateForNftIndex[_nftIndex] = _hashRate;

        emit SetHashRateForNftIndex(_nftIndex, _hashRate);
    }

    function setHashRateForNftIdRange(
        uint256 _nftIndex,
        uint256 _nftIdMin,
        uint256 _nftIdMax,
        uint256 _hashRate
    ) external {
        require(openBbqFieldsV2Router.peripheryOwner(peripheryIndexOnRouter) == msg.sender, "not peripheryOwner");

        for (uint256 i = _nftIdMin; i <= _nftIdMax; i++) {
            hashRateForNftId[_nftIndex][i] = _hashRate;
        }

        emit SetHashRateForNftIdRange(_nftIndex, _nftIdMin, _nftIdMax, _hashRate);
    }

    function setRewardEmission(uint256 _rewardTokenIndex, uint256 _emissionRate) external { // can be points by default until rewards are deposited on the router.
        require(openBbqFieldsV2Router.peripheryOwner(peripheryIndexOnRouter) == msg.sender, "not peripheryOwner");

        rewardEmissionRate[_rewardTokenIndex] = _emissionRate;
        
        emit SetRewardEmission(_rewardTokenIndex, _emissionRate);
    }

    function calculatePoint(uint256 _nftIndex, uint256 _nftId) public view returns(uint256) {
        uint256 stakedTimestamp = openBbqFieldsV2Router.stakedUseByPeriphery(peripheryIndexOnRouter, _nftIndex, _nftId);
        require(stakedTimestamp != 0, 'not stake on this periphery');

        uint256 _nftIndexHashRate = hashRateForNftIndex[_nftIndex];
        uint256 _nftIdHashRate = hashRateForNftId[_nftIndex][_nftId];
        uint256 _nftHashRate = _nftIdHashRate == 0 ? _nftIndexHashRate : _nftIdHashRate;

        return (block.timestamp - stakedTimestamp) * baseHashRate * bonusMultiplier * _nftHashRate;
    }

    function calculateReward(
        uint256 _nftIndex,
        uint256 _nftId,
        uint256 _rewardTokenIndex
    ) public view returns(uint256) {
        uint256 _point = calculatePoint(_nftIndex, _nftId);
        uint256 _tokenEmission = rewardEmissionRate[_rewardTokenIndex];

        return _point * _tokenEmission;
    }

    function _requestSendRewardFromRouter(
        uint256 _rewardTokenIndex,
        address _claimedTo,
        uint256 _claimedAmount
    ) internal {
        openBbqFieldsV2Router.sendRewardFromPeriphery(peripheryIndexOnRouter, _claimedTo, _rewardTokenIndex, _claimedAmount);
    }

    function _requestSyncNftStakedAtFromRouter(uint256 _nftIndex, uint256 _nftId) internal {
        openBbqFieldsV2Router.syncNftStakedAtFromPeriphery(peripheryIndexOnRouter, _nftIndex, _nftId);
    }

    function claimReward(
        uint256 _nftIndex,
        uint256 _nftId,
        uint256 _rewardTokenIndex,
        address _claimedTo
    ) external {
        require(openBbqFieldsV2Router.stakedData(_nftIndex, _nftId).nftOwnerOf == msg.sender, "not nft owner");
        uint256 _claimedAmount = calculateReward(_nftIndex, _nftId, _rewardTokenIndex);

        _requestSyncNftStakedAtFromRouter(_nftIndex, _nftId);

        _requestSendRewardFromRouter(_rewardTokenIndex, _claimedTo, _claimedAmount);
        
        emit ClaimReward(_nftIndex, _nftId, _rewardTokenIndex, _claimedTo, _claimedAmount);
    }
}
