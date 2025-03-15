// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenBbqFieldsV2Router is Ownable {
    uint256 public hooksCount;
    mapping(uint256 => address) public hooks;
    mapping(address => uint256) public hooksIndexOf;

    uint256 public peripheryCount;
    mapping(uint256 => address) public periphery;
    mapping(address => uint256) public peripheryIndexOf;
    mapping(uint256 => address) public peripheryOwner;
    mapping(uint256 => uint256) public hookUseByPeriphery; // immutable, read-only
    mapping(uint256 rewardTokenIndex => mapping(uint256 peripheryIndex => uint256 rewardTokenAmount)) public rewardTokenUseByPeriphery; // allow multiple token rewards, the default is no reward token

    uint256 public rewardTokensCount;
    mapping(uint256 => address) public rewardTokens;
    mapping(address => uint256) public rewardTokensIndexOf;
   
    uint256 public nftsCount;
    mapping(uint256 => address) public nfts;
    mapping(address => uint256) public nftsIndexOf;

    struct StakedData {
        address nftOwnerOf;
        uint256 nftStakedAt;
    }
    mapping(uint256 nftIndex => mapping(uint256 nftId => StakedData)) public stakedData;
    mapping(uint256 peripheryIndex => mapping(uint256 nftIndex => mapping(uint256 nftId => uint256 timestamp))) public stakedUseByPeriphery; // the same NFT can be used on multiple peripheries

    struct FeeForCreatePeriphery {
        address feeCollector;
        uint256 feeAmount;
    }
    FeeForCreatePeriphery public feeForCreatePeriphery;

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

    constructor() Ownable(msg.sender) {}

    function setFeeForCreatePeriphery(address _feeCollector, uint256 _feeAmount) external onlyOwner {
        feeForCreatePeriphery.feeCollector = _feeCollector;
        feeForCreatePeriphery.feeAmount = _feeAmount;
    }

    function setHook(address _hookAddr) external {
        require(hooksIndexOf[_hookAddr] == 0, "duplicate hook address");

        hooksCount++;
        hooks[hooksCount] = _hookAddr;
        hooksIndexOf[_hookAddr] = hooksCount;
    }

    function setRewardToken(address _rewardTokenAddr) external {
        require(rewardTokensIndexOf[_rewardTokenAddr] == 0, "duplicate reward token address");

        rewardTokensCount++;
        rewardTokens[rewardTokensCount] = _rewardTokenAddr;
        rewardTokensIndexOf[_rewardTokenAddr] = rewardTokensCount;
    }

    function setNft(address _nftAddr) external {
        require(nftsIndexOf[_nftAddr] == 0, "duplicate nft address");

        nftsCount++;
        nfts[nftsCount] = _nftAddr;
        nftsIndexOf[_nftAddr] = nftsCount;
    }

    function setPeriphery(address _peripheryAddr, address _peripheryOwner) external payable {
        require(hooksIndexOf[msg.sender] != 0, "not fieldsHookFactory caller");
        require(msg.value == feeForCreatePeriphery.feeAmount, "inadequate for the creation fee");
        require(peripheryIndexOf[_peripheryAddr] == 0, "duplicate periphery address");

        payable(feeForCreatePeriphery.feeCollector).transfer(feeForCreatePeriphery.feeAmount); // collect fees from periphery creators
        peripheryCount++;
        periphery[peripheryCount] = _peripheryAddr;
        peripheryIndexOf[_peripheryAddr] = peripheryCount;
        peripheryOwner[peripheryCount] = _peripheryOwner;
        hookUseByPeriphery[peripheryCount] = hooksIndexOf[msg.sender];
    }

    function setPeripheryOwner(uint256 _peripheryIndex, address _newOwner) external {
        require(peripheryOwner[_peripheryIndex] == msg.sender, "not peripheryOwner");

        emit SetPeripheryOwner(_peripheryIndex, peripheryOwner[_peripheryIndex], _newOwner);

        peripheryOwner[_peripheryIndex] = _newOwner;
    }

    function setPeripheryReward(
        uint256 _peripheryIndex,
        uint256 _rewardTokenIndex,
        uint256 _rewardTokenAmount
    ) external {
        require(peripheryOwner[_peripheryIndex] == msg.sender, "not peripheryOwner");

        IERC20(rewardTokens[_rewardTokenIndex]).transferFrom(msg.sender, address(this), _rewardTokenAmount);

        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndex] += _rewardTokenAmount;

        emit SetPeripheryReward(_peripheryIndex, peripheryOwner[_peripheryIndex], _rewardTokenIndex, _rewardTokenAmount);
    }

    function migratePeripheryRewardToHook(
        uint256 _peripheryIndexFrom,
        uint256 _peripheryIndexTo,
        uint256 _rewardTokenIndex,
        uint256 _migrateAmount
    ) external {
        require(peripheryOwner[_peripheryIndexFrom] == msg.sender, "not peripheryOwner");

        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndexFrom] -= _migrateAmount;
        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndexTo] += _migrateAmount;

        emit MigratePeripheryRewardToHook(_peripheryIndexFrom, _peripheryIndexTo, _rewardTokenIndex, _migrateAmount);
    }

    function migratePeripheryRewardToAddr(
        uint256 _peripheryIndex,
        address _migrateTo,
        uint256 _rewardTokenIndex,
        uint256 _migrateAmount
    ) external {
        require(peripheryOwner[_peripheryIndex] == msg.sender, "not peripheryOwner");

        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndex] -= _migrateAmount;

        IERC20(rewardTokens[_rewardTokenIndex]).transfer(_migrateTo, _migrateAmount);

        emit MigratePeripheryRewardToAddr(_peripheryIndex, _migrateTo, _rewardTokenIndex, _migrateAmount);
    }

    function sendRewardFromPeriphery(
        uint256 _peripheryIndex,
        address _claimedTo,
        uint256 _rewardTokenIndex,
        uint256 _claimedAmount
    ) external {
        require(periphery[_peripheryIndex] == msg.sender, "not periphery caller");

        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndex] -= _claimedAmount;

        IERC20(rewardTokens[_rewardTokenIndex]).transfer(_claimedTo, _claimedAmount);
        
        emit SendRewardFromPeriphery(_peripheryIndex, _claimedTo, _rewardTokenIndex, _claimedAmount);
    }

    function syncNftStakedAtFromPeriphery(
        uint256 _peripheryIndex,
        uint256 _nftIndex,
        uint256 _nftId
    ) external {
        require(periphery[_peripheryIndex] == msg.sender, "not periphery caller");
        require(stakedUseByPeriphery[_peripheryIndex][_nftIndex][_nftId] != 0, "no allowance");

        stakedUseByPeriphery[_peripheryIndex][_nftIndex][_nftId] = block.timestamp;

        emit SyncNftStakedAtFromPeriphery(_peripheryIndex, _nftIndex, _nftId);
    }

    function stealNftStakedFromPeriphery(
        uint256 _peripheryIndex,
        uint256 _nftIndex,
        uint256 _nftId,
        address _robber
    ) external { // for gamification purposes, please ensure hook security
        require(periphery[_peripheryIndex] == msg.sender, "not periphery caller");
        require(stakedUseByPeriphery[_peripheryIndex][_nftIndex][_nftId] != 0, "no allowance");

        IERC721(nfts[_nftIndex]).transferFrom(address(this), _robber, _nftId);

        delete stakedData[_nftIndex][_nftId];

        emit StealNftStakedFromPeriphery(_peripheryIndex, _nftIndex, _nftId, _robber);
    }

    function allowStakedUseByPeriphery(
        uint256 _peripheryIndex,
        uint256 _nftIndex,
        uint256 _nftId
    ) external {
        require(stakedData[_nftIndex][_nftId].nftOwnerOf == msg.sender, "not nft owner");

        stakedUseByPeriphery[_peripheryIndex][_nftIndex][_nftId] = block.timestamp;

        emit AllowStakedUseByPeriphery(msg.sender, _peripheryIndex, _nftIndex, _nftId);
    }

    function revokeStakedUseByPeriphery(
        uint256 _peripheryIndex,
        uint256 _nftIndex,
        uint256 _nftId
    ) external {
        require(stakedData[_nftIndex][_nftId].nftOwnerOf == msg.sender, "not nft owner");

        delete stakedUseByPeriphery[_peripheryIndex][_nftIndex][_nftId];

        emit RevokeStakedUseByPeriphery(msg.sender, _peripheryIndex, _nftIndex, _nftId);
    }

    function nftStake(uint256 _nftIndex, uint256 _nftId) external {
        IERC721(nfts[_nftIndex]).transferFrom(msg.sender, address(this), _nftId);

        stakedData[_nftIndex][_nftId].nftOwnerOf = msg.sender;
        stakedData[_nftIndex][_nftId].nftStakedAt = block.timestamp;

        emit NftStaked(msg.sender, _nftIndex, _nftId);
    }

    function nftUnstake(uint256 _nftIndex, uint256 _nftId) external {
        require(stakedData[_nftIndex][_nftId].nftOwnerOf == msg.sender, "not nft owner");

        IERC721(nfts[_nftIndex]).transferFrom(address(this), msg.sender, _nftId);

        delete stakedData[_nftIndex][_nftId];

        emit NftUnstaked(msg.sender, _nftIndex, _nftId);
    }

    function emergencyWithdrawNft(uint256 _nftIndex, uint256 _nftId) external onlyOwner {
        IERC721(nfts[_nftIndex]).transferFrom(address(this), stakedData[_nftIndex][_nftId].nftOwnerOf, _nftId);
        
        emit EmergencyWithdrawNft(stakedData[_nftIndex][_nftId].nftOwnerOf, _nftIndex, _nftId);

        delete stakedData[_nftIndex][_nftId];
    }

    function emergencyWithdrawRewardToken(
        uint256 _peripheryIndex,
        uint256 _rewardTokenIndex,
        uint256 _migrateAmount
    ) external onlyOwner {
        rewardTokenUseByPeriphery[_rewardTokenIndex][_peripheryIndex] -= _migrateAmount;

        IERC20(rewardTokens[_rewardTokenIndex]).transfer(peripheryOwner[_peripheryIndex], _migrateAmount);

        emit EmergencyWithdrawRewardToken(_peripheryIndex, peripheryOwner[_peripheryIndex], _rewardTokenIndex, _migrateAmount);
    }
}
