// SPDX-License-Identifier: MIT
// The line above is recommended and let you define the license of your contract
// Solidity files have to start with this pragma.
// It will be used by the Solidity compiler to validate its version.
pragma solidity ^0.8.0;
import "./AccessControlEnumerableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./EnumerableSet.sol";
import "./IRegistry.sol";
import "./IConfig.sol";

contract Registry is
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    IRegistry
{
    IConfig public override config;
    EnumerableSet.Bytes32Set private integration;
    EnumerableSet.AddressSet private integrationAddress;

    function _initialize(IConfig c) external initializer {
        // bound
        config = c;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function _integrationToBytes32(Integration memory input)
        internal
        pure
        returns (bytes32)
    {
        return
            bytes32(input.name) |
            (bytes32(bytes1(uint8(input.integrationType))) >> 88) |
            (bytes32(bytes20(input.integration)) >> 96);
    }

    function _bytes32ToIntegration(bytes32 input)
        internal
        pure
        returns (Integration memory result)
    {
        result = Integration({
            name: bytes11(input),
            integrationType: uint8(bytes1(input << 88)) == 0
                ? IntegrationType.Bridge
                : IntegrationType.Farm,
            integration: address(bytes20(input << 96))
        });
    }

    function getIntegrations()
        external
        view
        override
        returns (Integration[] memory result)
    {
        return _getIntegrations();
    }

    function integrationExist(address input)
        external
        view
        override
        returns (bool)
    {
        // Shengda: Using EnumberableSet for .....
        return EnumerableSet.contains(integrationAddress, input);
    }

    function _getIntegrations()
        internal
        view
        returns (Integration[] memory result)
    {
        // Shengda: Using EnumberableSet for .....
        bytes32[] memory values = EnumerableSet.values(integration);
        result = new Integration[](values.length);
        for (uint256 i; i < values.length; i++) {
            result[i] = _bytes32ToIntegration(values[i]);
        }
    }

    function registerIntegrations(Integration[] memory input)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // require(input.length < type(uint8).max, "RG2");
        for (uint8 i; i < input.length; i++) {
            bytes32 u = _integrationToBytes32(input[i]);
            EnumerableSet.add(integration, u);
            EnumerableSet.add(integrationAddress, input[i].integration);
        }
    }

    function unregisterIntegrations(Integration[] memory input)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint8 i; i < input.length; i++) {
            bytes32 u = _integrationToBytes32(input[i]);
            EnumerableSet.remove(integration, u);
            EnumerableSet.remove(integrationAddress, input[i].integration);
        }
    }

    function portfolio(address user)
        external
        view
        returns (AccountPosition[] memory result)
    {
        IRegistry.Integration[] memory itrxn = _getIntegrations();
        AccountPosition[] memory temp = new AccountPosition[](itrxn.length);
        uint8 count;
        for (uint8 i; i < itrxn.length; i++) {
            if (itrxn[i].integrationType != IRegistry.IntegrationType.Farm) {
                continue;
            }
            count++;
            temp[i].integration = itrxn[i];
            temp[i].position = IFarm(itrxn[i].integration).position(user);
        }
        result = new AccountPosition[](count);
        for (uint8 j; j < count; j++) {
            result[j] = temp[j];
        }
    }
}

