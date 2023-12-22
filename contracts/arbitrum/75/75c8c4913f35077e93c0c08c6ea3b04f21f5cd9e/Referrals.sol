// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IReferrals.sol";

contract Referrals is Ownable, IReferrals {

    address public protocol;
    mapping(address trader => address referrer) public referral;
    mapping(address referrer => uint) public refTier;
    uint[] public tiers;
    mapping(address referrer => uint) public totalFees;
    mapping(address => uint256) public tigAssetValue;
    uint[] public requirement;

    // Events
    event Referred(address referredTrader, address referrer);

    // Modifiers
    modifier onlyProtocol() {
        require(_msgSender() == address(protocol), "!Protocol");
        _;
    }

    constructor() {
        tiers = [50e4, 100e4, 125e4, 150e4];
        requirement = [0, 1000e18, 5000e18, 50000e18];
    }

    /**
    * @notice set the ref data
    * @dev only callable by trading
    * @param _referredTrader address of the trader
    * @param _referrer address of the referrer
    */
    function setReferred(address _referredTrader, address _referrer) external onlyProtocol {
        if (referral[_referredTrader] != address(0) || _referrer == address(0) || _referredTrader == _referrer) return;
        referral[_referredTrader] = _referrer;
        emit Referred(_referredTrader, _referrer);
    }

    function getReferred(address _trader) external view returns (address _referrer, uint256 _referrerFees) {
        _referrer = referral[_trader];
        if(_referrer != address(0)) {
            _referrerFees = tiers[refTier[_referrer]];
        } else {
            _referrerFees = 0;
        }
    }

    // 0 default first tier: 5% - no fees required
    // 1 second tier: 10% - $1000 (10M crypto volume)
    // 2 third tier: 12.5% - $5000 (50M crypto volume)
    function addRefFees(address _referrer, address _tigAsset, uint _fees) external onlyProtocol {
        if (_referrer == address(0)) return;
        _fees = _fees * tigAssetValue[_tigAsset] / 1e18;
        totalFees[_referrer] += _fees;

        uint256 _tier = refTier[_referrer];
        if (_tier >= 2) return;
        uint256 _totalFees = totalFees[_referrer];
        if(_totalFees >= requirement[2] && _tier < 2) {
            refTier[_referrer] = 2;
        } else if(_totalFees >= requirement[1] && _tier < 1) {
            refTier[_referrer] = 1;
        }
    }

    // Owner
    function setProtocol(address _protocol) external onlyOwner {
        protocol = _protocol;
    }

    function setRefTier(address _referrer, uint _tier) external onlyOwner {
        require(_tier < tiers.length, "!tier");
        refTier[_referrer] = _tier;
    }

    function setTiers(uint[] calldata _newTiers) external onlyOwner {
        require(_newTiers.length == 4, "!length");
        tiers = _newTiers;
    }

    function setTigAssetValue(address _tigAsset, uint256 _value) external onlyOwner {
        tigAssetValue[_tigAsset] = _value;
    }

    function setRequirement(uint[] calldata _requirement) external onlyOwner {
        require(_requirement.length == 4, "!length");
        requirement = _requirement;
    }
}
