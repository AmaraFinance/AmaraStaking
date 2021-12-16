pragma solidity ^0.5.8;

import "./SafeTRC20.sol";

contract DelegateAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of delegate
     */
    address public stakePoolImplementation;

    /**
     * @notice Pending brains of delegate
     */
    address public pendingStakePoolImplementation;
}

contract StakePoolStorage is DelegateAdminStorage {
    ITRC20 public stakeToken;
    ITRC20 public rewardToken;
}

contract StakePoolV1Storage is StakePoolStorage {
    uint256 public constant DURATION = 31_536_000; // 365day
    uint256 public startTime = 0;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
}
