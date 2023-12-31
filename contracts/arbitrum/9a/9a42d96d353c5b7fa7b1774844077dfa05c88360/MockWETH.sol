// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// contracts from OpenZeppelin Contracts (last updated v4.8.0)
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

/**
 * @title Mock Wrapped Ethereum
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 */
contract MockWETH is ERC20('Wrapped Ethereum', 'WETH'), Ownable {
    using SafeERC20 for ERC20;

    function mint(address to, uint256 quantity) public {
        _mint(to, quantity);
    }

    function burn(uint256 quantity) public {
        _burn(_msgSender(), quantity);
    }
}

