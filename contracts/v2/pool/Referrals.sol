// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "../../core/SafeOwnable.sol";
import "../../interfaces/IReferral.sol";

contract Referrals is SafeOwnable {
    
    mapping(address => address) internal _referrers;
    mapping(address => address[]) internal _recommended;

    mapping(address => bool) public isCaller;
    mapping(address => uint) public validReferral;
    mapping(address => bool) public isValidUser;
    mapping(address => bool) public isPartnerReward;
    mapping(address => bool) public _isPartner;

    constructor() {
        _referrers[msg.sender] = address(this);
    }

    function setReferrer(address _referrer) public virtual {
        require(_referrers[msg.sender] == address(0), "repeat operation");
        require(
            _referrers[_referrer] != address(0),
            "referrer does not have permission"
        );
        _referrers[msg.sender] = _referrer;
        _recommended[_referrer].push(msg.sender);
    }

    function isPartner(address account) public view returns (bool) {
        return _isPartner[account];
    }

    function referrers(address account)
        external
        view
        virtual
        returns (address)
    {
        return _referrers[account];
    }

    function setPartner(address account, bool state) public onlyOwner {
        _isPartner[account] = state;
    }

    function recommended(
        address account,
        uint256 page,
        uint256 size
    ) public view returns (uint256, address[] memory) {
        uint256 len = size;
        if (page * size + size > _recommended[account].length) {
            len = _recommended[account].length % size;
        }
        if (page > _recommended[account].length / size) {
            len = 0;
        }
        address[] memory _fans = new address[](len);
        uint256 startIdx = page * size;
        for (uint256 i = 0; i != size; i++) {
            if (startIdx + i >= _recommended[account].length) {
                break;
            }
            _fans[i] = _recommended[account][startIdx + i];
        }
        return (_recommended[account].length, _fans);
    }
}
