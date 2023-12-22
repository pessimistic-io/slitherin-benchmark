// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Ownable2Step.sol";
import "./IOutletDescriptor.sol";
import "./IOutletManagement.sol";
import "./StringConverter.sol";

contract OutletDescriptor is IOutletDescriptor, Ownable2Step {
    using StringConverter for address;
    using StringConverter for uint256;

    // storage

    // outletId -> properties data(json format) mapping
    mapping(uint256 => string) public propertiesMapping;

    /// events
    constructor(address initOwner) {
        require(initOwner != address(0), "Bad owner address");

        _transferOwnership(initOwner);
    }

    /// Admin Functions

    /**
     * @notice Admin restricted function to set additional properties for outlet
     */
    function setProperties(
        uint256 outletId,
        string memory properties
    ) public onlyOwner {
        propertiesMapping[outletId] = properties;
    }

    /// View Functions

    function getProperties(uint256 outletId) external view returns (string memory) {
        return propertiesMapping[outletId];
    }

    function outletURI(IOutletManagement outletManagement, uint256 outletId) external override view returns (string memory) {
        IOutletManagement.OutletData memory outletData = outletManagement.getOutletData(outletId);
        string memory properties = bytes(propertiesMapping[outletId]).length > 0 ? propertiesMapping[outletId] : "{}";

        return
            string(
                abi.encodePacked(
                    '{"name":"',
                    outletData.name,
                    '","manager":"',
                    outletData.manager.addressToString(),
                    '","isActive":"',
                    outletData.isActive ? "yes" : "no",
                    '","creditQuota":"',
                    outletData.creditQuota.toString(),
                    '","circulation":"',
                    outletData.circulation.toString(),
                    '","properties":',
                    properties,
                    "}"
                )
            );
    }
}

