// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./ERC20FlashMint.sol";

contract fSOL is ERC20, ERC20Burnable, Ownable, ERC20FlashMint {
    constructor() ERC20("fSOL", "fSOL") {

        // Mint enough tokens to provide 1,000,000 whole tokens with 18 decimals places.
        _mint(0x877C8bEec8b7B40C13594724eaf239Eec6A1FEe6, 1000000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {

        // 18 Decimals is the default but setting is explicitly here for clarity
        // and learning how to...
        return 18;
    }

    function mint(address to, uint256 amount) public onlyOwner {

        _mint(to, amount);
    }
}

