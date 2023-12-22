// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";

contract PooCoin5000 is ERC20, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address public treasury = 0xE8FFE751deA181025a9ACf3D6Bde8cdA5380F53F;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC20("xARXPoolFiller ", "XARXPF") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, treasury);

        _mint(treasury, 1 ether);
    }

    function mint(uint256 amount, address to) external onlyRole(ADMIN_ROLE) {
        _mint(to, amount);
    }

    function setTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        treasury = _treasury;
    }
}

