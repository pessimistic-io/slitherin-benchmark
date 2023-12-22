// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >0.8.0;

// Openzeppelin
import "./ERC20.sol";

import "./Base.sol";

contract Token is ERC20, Base {
    //** ======= Variables ======= */

    // Context
    mapping(address => bool) callers;

    //** ======= MODIFIERS ======= */
    modifier onlyCallers() {
        require(callers[msg.sender], 'Must be a caller');
        _;
    }

    //** ======= INITIALIZE ======= */

    /** @notice initialize */
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        callers[msg.sender] = true;

        _mint(msg.sender, 69_420_000_000 * 1e9);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /** ====== MINT & BURN ======== */
    function mint(address _account, uint256 _amount) external onlyCallers {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyCallers {
        _burn(_account, _amount);
    }

    function burn(uint256 _amount) public virtual {
        _burn(msg.sender, _amount);
    }

    /** setCaller
        Description: Allows account to mint/burn
        @param account {address}
        @param caller {bool}
     */
    function setCaller(address account, bool caller) external onlyOwner {
        callers[account] = caller;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, IERC20(tokenAddress).balanceOf(address(this)));
    }

    function rescueEth() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'PEPEOHM: ETH_TRANSFER_FAILED');
    }
}

