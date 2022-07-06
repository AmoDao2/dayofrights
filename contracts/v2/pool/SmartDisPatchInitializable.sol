// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";

import "hardhat/console.sol";

contract SmartDisPatchInitializable is Ownable, Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The address of the smart chef factory
    address public SMART_DISPATCH_FACTORY;

    uint256 private reserve;
    uint256 private lastTime;
    uint256 private rewardLastStored;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private userRewardStored;
    mapping(address => uint256) private newReward;

    IERC20 public rewardToken;
    mapping(address => uint256) public rewardPair;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor() {
        SMART_DISPATCH_FACTORY = msg.sender;
    }

    function initialize(address rewardToken_) external initializer {
        require(msg.sender == SMART_DISPATCH_FACTORY, "Not factory");
        rewardToken = IERC20(rewardToken_);
        transferOwnership(msg.sender);
    }

    modifier updateDispatch(address account) {
        rewardLastStored = rewardPer();

        uint256 balance = rewardToken.balanceOf(address(this));
        reserve = balance;

        if (account != address(0)) {
            newReward[account] = available(account);
            userRewardStored[account] = rewardLastStored;
        }
        _;
    }

    function lastReward() private view returns (uint256) {
        if (_totalSupply == 0) {
            return 0;
        }
        uint256 balance = rewardToken.balanceOf(address(this));
        return balance.sub(reserve);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function rewardPer() private view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardLastStored;
        }
        return rewardLastStored.add(lastReward().mul(1e18).div(totalSupply()));
    }

    function stake(address account, uint256 amount)
        external
        updateDispatch(account)
        onlyOwner
    {
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Staked(account, amount);
    }

    function withdraw(address account, uint256 amount)
        external
        updateDispatch(account)
        onlyOwner
    {
        _totalSupply = _totalSupply.sub(amount);
        _balances[account] = _balances[account].sub(amount);
        emit Withdrawn(account, amount);
    }

    function available(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPer().sub(userRewardStored[account]))
                .div(1e18)
                .add(newReward[account]);
    }

    function claim(address account) external updateDispatch(account) {
        uint256 reward = available(account);
        if (reward <= 0) {
            return;
        }
        reserve = reserve.sub(reward);
        newReward[account] = 0;

        rewardPair[account] = rewardPair[account].add(reward);

        rewardToken.safeTransfer(account, reward);
        emit RewardPaid(account, reward);
    }

    function sync() public updateDispatch(address(0)) {}
}
