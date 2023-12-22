// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./SupplyToken.sol";

library DeployStrategyTokenLogic {
    function deployStrategyToken(address _marginTokenAddress, address _tokenAddress) external returns (address) {
        IERC20Metadata marginToken = IERC20Metadata(_marginTokenAddress);
        IERC20Metadata erc20 = IERC20Metadata(_tokenAddress);

        return address(
            new SupplyToken(
                address(this),
                string.concat(
                    string.concat("Predy-ST-", erc20.name()),
                    string.concat("-", marginToken.name())
                ),
                string.concat(
                    string.concat("pst", erc20.symbol()),
                    string.concat("-", marginToken.symbol())
                ),
                marginToken.decimals()
            )
        );
    }
}

