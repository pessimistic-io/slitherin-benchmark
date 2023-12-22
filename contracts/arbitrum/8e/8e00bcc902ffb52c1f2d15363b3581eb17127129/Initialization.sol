// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./Kernel.sol";
import "./RADToken.sol";

contract Initialization is Policy {
    RADToken public token;
    address public immutable CONFIGURATOR;

    constructor(Kernel _kernel) Policy(_kernel) {
        CONFIGURATOR = msg.sender;
    }

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TOKEN");
        token = RADToken(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("TOKEN"), RADToken.mint.selector);
        requests[1] = Permissions(
            toKeycode("TOKEN"),
            RADToken.setMaxSupply.selector
        );
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == CONFIGURATOR, "Only configurator can mint");
        token.mint(_to, _amount);
    }

    function airdrop(RADToken oldToken, address[] calldata _tos) external {
        require(msg.sender == CONFIGURATOR, "Only configurator can mint");

        uint256 length = _tos.length;

        for (uint256 i = 0; i < length; ) {
            address to = _tos[i];
            uint256 amount = oldToken.balanceOf(to);

            if (amount > 0) {
                token.mint(to, amount);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setMaxSupply() external {
        require(msg.sender == CONFIGURATOR, "Only configurator can set max");
        token.setMaxSupply(2e6 * 1e18); // 200k supply
    }
}

