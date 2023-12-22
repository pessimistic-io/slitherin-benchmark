

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;

import "./access_Ownable.sol";
import "./security_ReentrancyGuard.sol";
import "./IGasStation.sol";
import "./Constant.sol";


contract GasStation is IGasStation, ReentrancyGuard, Ownable {

    address public controller; // only AccountFactory can add a user

    uint public gasPerUnit =  1e14;
    uint public maxUnitsPerClaim = 5;

    struct Info {
        uint count;
        uint claimPointer;
        bool valid;
    }
    mapping(address => Info) private _infoMap;

    constructor(address owner, address ctrl) {
        require(owner != Constant.ZERO_ADDRESS && ctrl != Constant.ZERO_ADDRESS, "Invalid address");
        controller = ctrl;
        transferOwnership(owner);
    }

    // Allow receive ETH
    receive() external payable {
    }

    function configure(uint gasPU, uint maxUPC) external onlyOwner {
        require(gasPU > 0 && maxUPC > 0, "Invalid params");
        gasPerUnit = gasPU;
        maxUnitsPerClaim = maxUPC;
    }

    // Add user's 1CT account
    function addUser(address user) external override {
        require(controller == msg.sender, "Invalid controller");
        _infoMap[user].valid = true;
    }

    // User must be added previously. Otherwise, exit in silence.
    function recordUsage(address user) external override {
        Info storage info = _infoMap[user];
        if (info.valid) {
            _infoMap[user].count++;
        }
    }

    function  queryClaimableGas(address user) external view returns (uint) {
        Info storage info = _infoMap[user];
        return (info.count - info.claimPointer) * gasPerUnit;
    }

    function claimGas() external nonReentrant {

        Info storage info = _infoMap[msg.sender];
        require(info.count > 0, "Nothing to claim");
        uint gas = _getGas(info);
        if (gas > 0) {
            info.claimPointer = info.count; // set pointer to top
            // transfer gas to user
            (bool success, ) = msg.sender.call{value: gas}("");
            require(success, "Gas claim failed");
        }
    }

    function _getGas(Info storage info) private view returns (uint) {
        uint num = info.count - info.claimPointer;
        return _min(num, maxUnitsPerClaim) * gasPerUnit;
    }

    function _min(uint a, uint b) private pure returns (uint) {
        return a > b ? b : a ;
    }
}



