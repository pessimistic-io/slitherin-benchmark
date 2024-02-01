// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;

import "./Authentication.sol";
import "./SafeERC20.sol";

import "./IVault.sol";
import "./IBalancerToken.sol";

import "./IBALTokenHolder.sol";

/**
 * @dev This contract simply holds the BAL token and delegates to Balancer Governance the permission to withdraw it. It
 * is intended to serve as the recipient of automated BAL minting via the liquidity mining gauges, allowing for the
 * final recipient of the funds to be configurable without having to alter the gauges themselves.
 *
 * There is also a separate auxiliary function to sweep any non-BAL tokens sent here by mistake.
 */
contract BALTokenHolder is IBALTokenHolder, Authentication {
    using SafeERC20 for IERC20;

    IBalancerToken private immutable _balancerToken;
    IVault private immutable _vault;

    string private _name;

    constructor(
        IBalancerToken balancerToken,
        IVault vault,
        string memory name
    ) Authentication(bytes32(uint256(address(this)))) {
        // BALTokenHolder is often deployed from a factory for convenience, but it uses its own address instead of
        // the factory's as a disambiguator to make sure the action IDs of all instances are unique, reducing likelihood
        // of errors.

        _balancerToken = balancerToken;
        _vault = vault;
        _name = name;
    }

    function getBalancerToken() external view returns (IBalancerToken) {
        return _balancerToken;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function getName() external view returns (string memory) {
        return _name;
    }

    function getAuthorizer() public view returns (IAuthorizer) {
        return getVault().getAuthorizer();
    }

    function _canPerform(bytes32 actionId, address account) internal view override returns (bool) {
        return getAuthorizer().canPerform(actionId, account, address(this));
    }

    function withdrawFunds(address recipient, uint256 amount) external override authenticate {
        IERC20(_balancerToken).safeTransfer(recipient, amount);
    }

    function sweepTokens(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external override authenticate {
        require(token != _balancerToken, "Cannot sweep BAL");
        IERC20(token).safeTransfer(recipient, amount);
    }
}

