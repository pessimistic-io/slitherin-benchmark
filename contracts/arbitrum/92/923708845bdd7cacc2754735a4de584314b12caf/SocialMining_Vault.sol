// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract SocialMining_Vault is AccessControl, Ownable {
    using SafeMath for uint256;

    /* 40% SocialMining token allocation */
    uint256 public immutable Max = 8000000000 ether;

    /* Admin role for daily linear release */
    bytes32 public constant Admin = keccak256("Admin");

    /* Initialization for $MetaX & nextRelease timestamp & Admins */
    constructor(
        address _MetaX_addr,
        uint256 _nextRelease
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
        nextRelease = _nextRelease;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozenToken, "SocialMining_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract address */
    bool public frozenToken;

    function setFrozenToken () public onlyOwner {
        frozenToken = true;
    }

    /* SocialMining Smart Contract */
    address public SocialMining_addr;

    function setSocialMining (address newSocialMining_addr) public onlyOwner {
        require(!frozenSocialMining, "SocialMining_Vault: SocialMining Address is frozen.");
        SocialMining_addr = newSocialMining_addr;
    }

    /* Freeze the SocialMining contract address */
    bool public frozenSocialMining;

    function setFrozenSocialMining () public onlyOwner {
        frozenSocialMining = true;
    }

    /* SocialMining start @Feb 14th 2023 */
    uint256 public T0 = 1676332800;

    /* Daily release quota */
    uint256 public release = 5479452 ether;

    /* Daily linear release mechanism */
    uint256 public immutable intervals = 1 days;

    /* Track for next release timestamp */
    uint256 public nextRelease;

    /* Track for accumulative release in $MetaX */
    uint256 public accumRelease;

    /* Halving every 2 years */
    function Halve () public onlyOwner {
        require(block.timestamp > T0 + 730 days, "SocialMining_Vault: Please wait till the next halving.");
        release = release.div(2);
        T0 += 730 days;
    }

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Daily release to SocialMining only by Admins */
    function Release () public onlyRole(Admin) {
        require(block.timestamp > nextRelease, "SocialMining_Vault: Please wait for the next release.");
        require(SocialMining_addr != address(0), "SocialMining_Vault: Can't release to address(0).");
        MX.transfer(SocialMining_addr, release);
        accumRelease += release;
        nextRelease += intervals;
    }
}
