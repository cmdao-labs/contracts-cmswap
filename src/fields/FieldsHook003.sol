// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./interfaces/IOpenBbqFieldsV2Router.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FieldsHook003 is ERC20 {
    IOpenBbqFieldsV2Router public openBbqFieldsV2Router;
    uint256 public peripheryIndexOnRouter;
    IERC20 public esToken;
    uint256 public defaultVestingDuration;

    mapping(uint256 => uint256) public hashRateForNftIndex; // boarder NFTindex hashrate
    mapping(uint256 nftIndex => mapping(uint256 nftId => uint256)) public hashRateForNftId; // specific NFTid hashrate

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 endTime;
    }
    mapping(address => VestingSchedule[]) public vestings;

    event SetHashRateForNftIndex(uint256 indexed nftIndex, uint256 hashRate);
    event SetHashRateForNftIdRange(uint256 indexed nftIndex, uint256 indexed nftIdMin, uint256 indexed nftIdMax, uint256 hashRate);
    event VestingCreated(address indexed staker, uint256 amount, uint256 startTime, uint256 endTime);
    event RewardClaimed(address indexed staker, uint256 amount);

    constructor(
        string memory _rewardName,
        string memory _rewardSymbol,
        uint256 _peripheryIndexOnRouter,
        address _openBbqFieldsV2Router,
        address _esToken,
        uint256 _defaultVestingDuration
    ) ERC20(_rewardName, _rewardSymbol) {
        peripheryIndexOnRouter = _peripheryIndexOnRouter;
        openBbqFieldsV2Router = IOpenBbqFieldsV2Router(_openBbqFieldsV2Router);
        esToken = IERC20(_esToken);
        defaultVestingDuration = _defaultVestingDuration;
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

    function startVesting(
        uint256 _nftIndex,
        uint256 _nftId,
        uint256 _amount
    ) external {
        require(openBbqFieldsV2Router.stakedData(_nftIndex, _nftId).nftOwnerOf == msg.sender, "not nft owner");
        require(openBbqFieldsV2Router.stakedUseByPeriphery(peripheryIndexOnRouter, _nftIndex, _nftId) != 0, 'not stake on this periphery');

        esToken.transferFrom(msg.sender, address(this), _amount);

        uint256 _startTime = block.timestamp;
        uint256 _nftHashRate = hashRateForNftId[_nftIndex][_nftId] == 0 ? 
            hashRateForNftIndex[_nftIndex] :
            hashRateForNftId[_nftIndex][_nftId];
        uint256 _endTime = _startTime + ((defaultVestingDuration * _nftHashRate) / 100000);
        vestings[msg.sender].push(VestingSchedule({
            totalAmount: _amount,
            claimedAmount: 0,
            startTime: _startTime,
            endTime: _endTime
        }));

        emit VestingCreated(msg.sender, _amount, _startTime, _endTime);
    }

    function claimReward() external {
        uint256 _totalClaimable = getClaimableAmount(msg.sender);
        
        VestingSchedule[] storage schedules = vestings[msg.sender];
        for (uint256 i = 0; i < schedules.length; i++) {
            schedules[i].claimedAmount += (_vestedAmount(schedules[i]) - schedules[i].claimedAmount);
        }

        _mint(msg.sender, _totalClaimable);
        
        emit RewardClaimed(msg.sender, _totalClaimable);
    }

    function getClaimableAmount(address _staker) public view returns (uint256 totalClaimable) {
        VestingSchedule[] storage schedules = vestings[_staker];
        for (uint256 i = 0; i < schedules.length; i++) {
            totalClaimable += (_vestedAmount(schedules[i]) - schedules[i].claimedAmount);
        }
    }

    function _vestedAmount(VestingSchedule memory _schedule) private view returns (uint256) {
        if (block.timestamp >= _schedule.endTime) {
            return _schedule.totalAmount;
        } else {
            return (_schedule.totalAmount * (block.timestamp - _schedule.startTime)) / (_schedule.endTime - _schedule.startTime);
        }
    }
}
