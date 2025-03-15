// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./interfaces/IOpenBbqFieldsV2Router.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FieldsHook002 is ERC20 {
    IOpenBbqFieldsV2Router public openBbqFieldsV2Router;
    uint256 public peripheryIndexOnRouter;

    mapping(uint256 => bool) public isNftIndexEligible;

    uint256 public currentBlock = 1;
    uint256 public currentDifficulty = 1;
    uint256 public lastBlockTime = block.timestamp;
    uint256 public adjustmentInterval;
    uint256 public targetTime;

    event SetNftIndexEligible(uint256 indexed nftIndex, bool isEligible);
    event BlockMined(address indexed minerOwner, uint256 indexed nftIndex, uint256 indexed nftId, uint256 solvedBlockNumber, uint256 solvedBaseDifficulty, uint256 solvedMinerDifficulty, bytes32 solvedHash, uint256 elapsedTime, uint256 blockReward);

    constructor(
        string memory _rewardName,
        string memory _rewardSymbol,
        uint256 _peripheryIndexOnRouter,
        address _openBbqFieldsV2Router,
        uint256 _targetTime,
        uint256 _adjustmentInterval
    ) ERC20(_rewardName, _rewardSymbol) {
        peripheryIndexOnRouter = _peripheryIndexOnRouter;
        openBbqFieldsV2Router = IOpenBbqFieldsV2Router(_openBbqFieldsV2Router);
        targetTime = _targetTime;
        adjustmentInterval = _adjustmentInterval;
    }

    function setNftIndexEligible(uint256 _nftIndex, bool _isEligible) external {
        require(openBbqFieldsV2Router.peripheryOwner(peripheryIndexOnRouter) == msg.sender, 'not peripheryOwner');
        
        isNftIndexEligible[_nftIndex] = _isEligible;

        emit SetNftIndexEligible(_nftIndex, _isEligible);
    }

    function getBlockReward() public view returns(uint256) {
        uint256 demominator = (currentBlock / 100000) + 1;
        return 100 ether / (2 * demominator);
    }

    function sha256Hash(bytes memory data) public pure returns(bytes32) {
        return sha256(data);
    }

    function adjustDifficulty(uint256 _currentDiff, uint256 _actualTimePerBlock) internal view returns(uint256) {
        if (_actualTimePerBlock < targetTime) {
            return _currentDiff + 1;
        } else if (_actualTimePerBlock > targetTime) {
            return _currentDiff > 1 ? _currentDiff - 1 : 1;
        }
        return _currentDiff;
    }

    function submitPoW(
        uint256 _nftIndex,
        uint256 _nftId,
        uint256 _nonce,
        bytes32 _hash
    ) external {
        require(isNftIndexEligible[_nftIndex], 'nft index is not eligible');
        uint256 _stakedTimestamp = openBbqFieldsV2Router.stakedUseByPeriphery(peripheryIndexOnRouter, _nftIndex, _nftId);
        require(_stakedTimestamp != 0, 'not stake on this periphery');

        uint256 _elapsedTime = block.timestamp - lastBlockTime;
        uint256 _blockReward = getBlockReward();
        address _minerOwner = openBbqFieldsV2Router.stakedData(_nftIndex, _nftId).nftOwnerOf;
        uint256 _minerDiff =  currentDifficulty > ((_nftId % 100000) / 1000) ? currentDifficulty - ((_nftId % 100000) / 1000) : 1;
        bytes32 validHash = sha256(abi.encode(currentBlock, _nonce));
        require(validHash == _hash, 'invalid hash');
        require(validHash < bytes32(uint256(2 ** (256 - _minerDiff))), 'hash does not meet difficulty');

        emit BlockMined(_minerOwner, _nftIndex, _nftId, currentBlock, currentDifficulty, _minerDiff, _hash, _elapsedTime, _blockReward);

        currentBlock++;
        lastBlockTime = block.timestamp;
        if (currentBlock % adjustmentInterval == 0) {
            currentDifficulty = adjustDifficulty(currentDifficulty, _elapsedTime);
        }

        _mint(_minerOwner, _blockReward);
    }
}
