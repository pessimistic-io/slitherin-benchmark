// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./BehaviorSafetyMethods.sol";
import "./console.sol";

struct VestingAddressInfo {
    uint256 startTime;
    uint256 claimed;
    uint256 vested;
    uint256 allVestings;
    uint256 previousVestings;
    uint256 previousVestingsClaimable;
}

contract ComponentVestingRefillable is Ownable, BehaviorSafetyMethods {
    address addressManagedToken;
    IERC20 managedToken;
    uint256 vestingPeriod;
    mapping(address => VestingAddressInfo) vestings;

    constructor(address _addressManagedToken, uint256 _vestingSeconds) {
        addressManagedToken = _addressManagedToken;
        managedToken = IERC20(_addressManagedToken);
        vestingPeriod = _vestingSeconds;
    }

    function getTokensAmountClaimable(address _recipient) public view returns (uint256) {
        VestingAddressInfo memory info = vestings[_recipient];
        return _calculateAvailableForVesting(info) + info.previousVestingsClaimable;
    }

    function getTokensAmountTotalVested(address _recipient) public view returns (uint256) {
        VestingAddressInfo memory info = vestings[_recipient];
        return info.allVestings;
    }

    function getTokensAmountUnclaimed(address _recipient) public view returns (uint256) {
        VestingAddressInfo memory info = vestings[_recipient];
        return info.vested - info.claimed + info.previousVestingsClaimable;
    }

    function getTokensAmountClaimed(address _recipient) public view returns (uint256) {
        VestingAddressInfo memory info = vestings[_recipient];
        return info.claimed + info.previousVestings - info.previousVestingsClaimable;
    }

    function depositTokens(address _recipient, uint256 _amount) public {
        depositTokensFrom(msg.sender, _recipient, _amount);
    }

    function depositTokensFrom(address _from, address _recipient, uint256 _amount) public {
        require(_amount > 0, "Missing amount");

        managedToken.transferFrom(_from, address(this), _amount);

        VestingAddressInfo memory info = vestings[_recipient];
        if (info.startTime == 0) {
            info.startTime = block.timestamp;
            info.vested = _amount;
            info.allVestings = _amount;
        } else {
            uint256 claimable = _calculateAvailableForVesting(info);

            uint256 vestingTillNow = info.claimed + claimable;
            uint256 transferToNewVesting = info.vested - vestingTillNow;
            info.previousVestings += vestingTillNow;
            info.previousVestingsClaimable += claimable;
            info.vested = _amount + transferToNewVesting;
            info.claimed = 0;
            info.startTime = block.timestamp;
            info.allVestings += _amount;
        }
        vestings[_recipient] = info;
    }

    function claim() public {
        VestingAddressInfo memory info = vestings[msg.sender];
        uint256 claimable = _calculateAvailableForVesting(info);
        uint256 claimableAll = claimable + info.previousVestingsClaimable;

        require(claimableAll > 0, "There is nothing to claim");

        info.previousVestingsClaimable = 0;
        info.claimed += claimable;
        vestings[msg.sender] = info;

        managedToken.transfer(msg.sender, claimableAll);
    }

    function _calculateAvailableForVesting(VestingAddressInfo memory info) internal view returns (uint256) {
        uint256 elapsedTime = Math.min(block.timestamp - info.startTime, vestingPeriod);

        uint256 availableForVestingAll = (info.vested * elapsedTime) / vestingPeriod;

        uint256 availableForVesting = availableForVestingAll - info.claimed;

        return availableForVesting;
    }
}

