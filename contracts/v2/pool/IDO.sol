// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";
import "../../interfaces/IReferral.sol";
import "../../nft/IFO.sol";

contract IDO is Ownable, ReentrancyGuard {

    IERC20 public token;
    IReferral public referral;
    IFO public ifos;

    uint256 public tokenAmount;

    mapping(address => uint256) public userAmount;

    constructor(
        address _token,
        address _referral,
        address _ifos,
        uint256 _tokenAmount
    ) {
        token = IERC20(_token);
        referral = IReferral(_referral);
        ifos = IFO(_ifos);
        tokenAmount = _tokenAmount;
    }

    function ido() external nonReentrant {
        uint256 reward = pending(msg.sender);
        if (reward <= 0) return;
        token.transfer(msg.sender, reward);
        userAmount[msg.sender] = reward;
    }

    function pending(address _account) public view returns (uint256) {
        if (!referral.isPartner(_account) || !isIfo(_account)) return 0;
        if (userAmount[_account] > 0) return 0;
        return tokenAmount;
    }

    function isIfo(address account) internal view returns (bool) {
        if (ifos.isOperated(account, 1)) return true;
        if (ifos.isOperated(account, 2)) return true;
        if (ifos.isOperated(account, 3)) return true;
        return false;
    }

    function adminConfig(
        address _token,
        address _account,
        uint256 _value
    ) public onlyOwner {
        IERC20(_token).transfer(_account, _value);
    }
}
