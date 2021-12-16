pragma solidity ^0.5.8;

import "./SafeMath.sol";
import "./SafeTRC20.sol";
import "./Math.sol";
import "./StakePoolStorage.sol";
import "./Delegate.sol";

contract LPTokenWrapper is StakePoolV1Storage {
    uint256 private _totalSupply;

    using SafeMath for uint256;
    using SafeTRC20 for ITRC20;

    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function _stake(uint256 amount, address account) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        stakeToken.safeTransferFrom(account, address(this), amount);
    }

    function _withdraw(uint256 amount, address account) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[account] = _balances[account].sub(amount);
        stakeToken.safeTransfer(account, amount);
    }
}

contract StakeBasePool is LPTokenWrapper {
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Rescue(address indexed dst, uint256 sad);
    event RescueToken(address indexed dst, address indexed token, uint256 sad);

    constructor() public {
        admin = msg.sender;
    }

    modifier checkStart() {
        require(block.timestamp >= startTime, "not start");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public updateReward(msg.sender) checkStart {
        require(amount > 0, "Cannot stake 0");
        super._stake(amount, msg.sender);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "Cannot withdraw 0");
        super._withdraw(amount, msg.sender);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        _withdraw(balanceOf(msg.sender), msg.sender);
    }

    function getReward(address account, uint256 amount) public {
        require(block.timestamp >= startTime, "not start");

        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }

        uint256 trueReward = earned(account);
        require(trueReward > 0, "trueReward error");

        rewards[account] = trueReward.sub(amount);
        rewardToken.safeTransfer(account, amount);
        emit RewardPaid(account, amount);
    }

    function notifyRewardAmount(uint256 rate)
        external
        updateReward(address(0))
    {
        require(adminOrInitializing(), "only admin can set reward");
        require(startTime > 0, "startTime is not set");
        // if (block.timestamp > startTime) {
        // if (block.timestamp >= periodFinish) {
        //     rewardRate = reward.div(DURATION);
        // } else {
        //     uint256 remaining = periodFinish.sub(block.timestamp);
        //     uint256 leftover = remaining.mul(rewardRate);
        //     rewardRate = reward.add(leftover).div(DURATION);
        // }
        // lastUpdateTime = block.timestamp;
        // periodFinish = block.timestamp.add(DURATION);
        // emit RewardAdded(reward);
        // } else {
        // rewardRate = reward.div(DURATION);
        // lastUpdateTime = startTime;
        // periodFinish = startTime.add(DURATION);
        // emit RewardAdded(reward);
        // }
        if (block.timestamp <= startTime) {
            lastUpdateTime = startTime;
        }
        rewardRate = rate;
        emit RewardAdded(rate);
    }

    function prolong(uint256 time) external {
        require(adminOrInitializing(), "only admin can prolong finish time");
        require(startTime > 0, "startTime is not set");
        periodFinish = periodFinish + time;
    }

    /**
     * @notice rescue simple transfered TRX.
     */
    function rescue(address payable to_, uint256 amount_) external {
        require(adminOrInitializing(), "only admin can rescue main token");
        require(to_ != address(0), "must not 0");
        require(amount_ > 0, "must gt 0");

        to_.transfer(amount_);
        emit Rescue(to_, amount_);
    }

    /**
     * @notice rescue simple transfered unrelated token.
     */
    function rescueToken(
        address to_,
        ITRC20 token_,
        uint256 amount_
    ) external {
        require(adminOrInitializing(), "only admin can rescue token");
        require(to_ != address(0), "must not 0");
        require(amount_ > 0, "must gt 0");
        // require(token_ != Token, "must not Token");
        // require(token_ != tokenAddr, "must not this lpToken");

        token_.transfer(to_, amount_);
        emit RescueToken(to_, address(token_), amount_);
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == stakePoolImplementation;
    }

    function _become(Delegate delegate) public {
        require(
            msg.sender == delegate.admin(),
            "only delegate admin can change brains"
        );
        require(delegate._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Set the start timestamp of the stake pool
     * @param _startTime The stake ERC20 token address
     */
    function _setStartTime(uint256 _startTime) public {
        require(adminOrInitializing(), "only admin can set start timestamp");
        require(_startTime > 0, "startTime must gt 0");
        if (startTime > 0) {
            require(startTime >= block.timestamp, "Stake has started");
        }

        startTime = _startTime;
        periodFinish = startTime.add(DURATION);
    }

    /**
     * @notice Set the contract address of the stake token
     * @param _tokenAddress The stake ERC20 token address
     */
    function _setTokenAddress(address _tokenAddress) public {
        require(adminOrInitializing(), "only admin can set token address");
        require(
            _tokenAddress != address(0),
            "tokenAddress cannot be equal to address(0)"
        );

        stakeToken = ITRC20(_tokenAddress);
    }

    /**
     * @notice Set the contract address of the reward token
     * @param _rewardTokenAddress The reward ERC20 token address
     */
    function _setRewardTokenAddress(address _rewardTokenAddress) public {
        require(
            adminOrInitializing(),
            "only admin can set reward token address"
        );
        require(
            _rewardTokenAddress != address(0),
            "rewardTokenAddress cannot be equal to address(0)"
        );

        rewardToken = ITRC20(_rewardTokenAddress);
    }
}
