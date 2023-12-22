// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./IReferrals.sol";

contract Referrals is Ownable, IReferrals {

    bool private isInit;
    address public protocol;
    mapping(address trader => address referrer) private _referral;

    // Events
    event Referred(address referredTrader, address referrer);

    // Modifiers
    modifier onlyProtocol() {
        require(_msgSender() == address(protocol), "!Protocol");
        _;
    }

    /**
    * @notice set the ref data
    * @dev only callable by trading
    * @param _referredTrader address of the trader
    * @param _referrer address of the referrer
    */
    function setReferred(address _referredTrader, address _referrer) external onlyProtocol {
        if (_referral[_referredTrader] != address(0) || _referrer == address(0) || _referredTrader == _referrer) return;
        _referral[_referredTrader] = _referrer;
        emit Referred(_referredTrader, _referrer);
    }

    function getReferred(address _trader) external view returns (address) {
        return _referral[_trader];
    }

    // Owner
    function setProtocol(address _protocol) external onlyOwner {
        protocol = _protocol;
    }
}
