// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";
import "./SafeERC20.sol";

contract OrbitrumToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    using SafeERC20 for IERC20;

    constructor() ERC20("Orbitrum", "ORB") ERC20Permit("Orbitrum") {
        _mint(owner(), 10000000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

     /**
     * @notice Rescue ETH locked up in this contract.
     * @param _to       Recipient address
     */

    function withdrawETH(
        address _to,
        uint256 _amount        
    ) external payable onlyOwner{
        require(_to != address(0), "Zero address");

        (bool sent,) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        
    }

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param tokenContract ERC20 token contract address
     * @param to        Recipient address
     * @param amount    Amount to withdraw
     */
    function rescueERC20(
        IERC20 tokenContract,
        address to,
        uint256 amount
    ) external onlyOwner {        
        require(to != address(0), "Zero address");

        tokenContract.safeTransfer(to, amount);
    }

}
