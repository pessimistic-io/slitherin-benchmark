// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.13;

import { ERC20 } from "./ERC20.sol";
import { ERC20Permit } from "./draft-ERC20Permit.sol";

import { Token } from "./Token.sol";
import { ERC20Burnable } from "./ERC20Burnable.sol";

import { IVersioned } from "./IVersioned.sol";
import { Owned } from "./Owned.sol";
import { Utils } from "./Utils.sol";

import { IPoolToken } from "./IPoolToken.sol";

/**
 * @dev Pool Token contract
 */
contract PoolToken is IPoolToken, ERC20Permit, ERC20Burnable, Owned, Utils {
    Token private immutable _reserveToken;

    uint8 private _decimals;

    /**
     * @dev initializes a new PoolToken contract
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 initDecimals,
        Token initReserveToken
    ) ERC20(name, symbol) ERC20Permit(name) validAddress(address(initReserveToken)) {
        _decimals = initDecimals;
        _reserveToken = initReserveToken;
    }

    /**
     * @inheritdoc IVersioned
     */
    function version() external pure returns (uint16) {
        return 1;
    }

    /**
     * @dev returns the number of decimals used to get its user representation
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @inheritdoc IPoolToken
     */
    function reserveToken() external view returns (Token) {
        return _reserveToken;
    }

    /**
     * @inheritdoc IPoolToken
     */
    function mint(address recipient, uint256 amount) external onlyOwner validExternalAddress(recipient) {
        _mint(recipient, amount);
    }
}

