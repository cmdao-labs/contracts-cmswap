// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IOpenBbqFieldsV2Router {
    function hooksCount() external view returns (uint256);
    function hooks(uint256) external view returns (address);
    function hooksIndexOf(address) external view returns (uint256);

    function peripheryCount() external view returns (uint256);
    function periphery(uint256) external view returns (address);
    function peripheryIndexOf(address) external view returns (uint256);
    function peripheryOwner(uint256) external view returns (address);
    function hookUseByPeriphery(uint256) external view returns (uint256);
    function rewardTokenUseByPeriphery(uint256 rewardTokenIndex, uint256 peripheryIndex) external view returns (uint256 rewardTokenAmount);

    function rewardTokensCount() external view returns (uint256);
    function rewardTokens(uint256) external view returns (address);
    function rewardTokensIndexOf(address) external view returns (uint256);

    function nftsCount() external view returns (uint256);
    function nfts(uint256) external view returns (address);
    function nftsIndexOf(address) external view returns (uint256);

    struct StakedData {
        address nftOwnerOf;
        uint256 nftStakedAt;
    }
    function stakedData(uint256 nftIndex, uint256 nftId) external view returns (StakedData memory);
    function stakedUseByPeriphery(uint256 peripheryIndex, uint256 nftIndex, uint256 nftId) external view returns (uint256 timestamp);

    struct FeeForCreatePeriphery {
        address feeCollector;
        uint256 feeAmount;
    }
    function feeForCreatePeriphery() external view returns (FeeForCreatePeriphery memory);

    event SetPeripheryOwner(uint256 indexed peripheryIndex, address indexed oldOwner, address indexed newOwner);
    event SetPeripheryReward(uint256 indexed peripheryIndex, address indexed peripheryOwner, uint256 indexed rewardTokenIndex, uint256 rewardTokenAmount);
    event MigratePeripheryRewardToHook(uint256 indexed peripheryIndexFrom, uint256 indexed peripheryIndexTo, uint256 indexed rewardTokenIndex, uint256 migrateAmount);
    event MigratePeripheryRewardToAddr(uint256 indexed peripheryIndex, address indexed migrateTo, uint256 indexed rewardTokenIndex, uint256 migrateAmount);
    
    event SendRewardFromPeriphery(uint256 indexed peripheryIndex, address indexed claimedTo, uint256 indexed rewardTokenIndex, uint256 claimedAmount);
    event SyncNftStakedAtFromPeriphery(uint256 indexed peripheryIndex, uint256 indexed nftIndex, uint256 indexed nftId);
    event StealNftStakedFromPeriphery(uint256 indexed peripheryIndex, uint256 indexed nftIndex, uint256 nftId, address indexed robber);

    event AllowStakedUseByPeriphery(address indexed staker, uint256 indexed peripheryIndex, uint256 indexed nftIndex, uint256 nftId);
    event RevokeStakedUseByPeriphery(address indexed staker, uint256 indexed peripheryIndex, uint256 indexed nftIndex, uint256 nftId);
    event NftStaked(address indexed staker, uint256 indexed nftIndex, uint256 indexed nftId);
    event NftUnstaked(address indexed staker, uint256 indexed nftIndex, uint256 indexed nftId);

    event EmergencyWithdrawNft(address indexed staker, uint256 indexed nftIndex, uint256 indexed nftId);
    event EmergencyWithdrawRewardToken(uint256 indexed peripheryIndex, address indexed peripheryOwner, uint256 indexed rewardTokenIndex, uint256 migrateAmount);

    function setFeeForCreatePeriphery(address _feeCollector, address _feeToken, uint256 _feeAmount) external;

    function setHook(address) external;
    function setRewardToken(address) external;
    function setNft(address) external;

    function setPeriphery(address _peripheryAddr, address _peripheryOwner) external payable;
    function setPeripheryOwner(uint256 _peripheryIndex, address _newOwner) external;
    function setPeripheryReward(uint256 _peripheryIndex, uint256 _rewardTokenIndex, uint256 _peripheryRewardTokenAmount) external;
    function migratePeripheryRewardToHook(uint256 _peripheryIndexFrom, uint256 _peripheryIndexTo, uint256 _rewardTokenIndex, uint256 _migrateAmount) external;
    function migratePeripheryRewardToAddr(uint256 _peripheryIndex, address _migrateTo, uint256 _rewardTokenIndex, uint256 _migrateAmount) external;

    function sendRewardFromPeriphery(uint256 _peripheryIndex, address _claimedTo, uint256 _rewardTokenIndex, uint256 _claimedAmount) external;
    function syncNftStakedAtFromPeriphery(uint256 _peripheryIndex, uint256 _nftIndex, uint256 _nftId) external;
    function stealNftStakedFromPeriphery(uint256 _peripheryIndex, uint256 _nftIndex, uint256 _nftId, address _robber) external;

    function allowStakedUseByPeriphery(uint256 _peripheryIndex, uint256 _nftIndex, uint256 _nftId) external;
    function revokeStakedUseByPeriphery(uint256 _peripheryIndex, uint256 _nftIndex, uint256 _nftId) external;

    function nftStake(uint256 _nftIndex, uint256 _nftId) external;
    function nftUnstake(uint256 _nftIndex, uint256 _nftId) external;

    function emergencyWithdrawNft(uint256 _nftIndex, uint256 _nftId) external;
    function emergencyWithdrawRewardToken(uint256 _peripheryIndex, uint256 _rewardTokenIndex, uint256 _migrateAmount) external;
}
