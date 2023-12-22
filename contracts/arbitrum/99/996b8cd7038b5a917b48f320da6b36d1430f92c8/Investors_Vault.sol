// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Investors_Vault is AccessControl, Ownable {
    using SafeMath for uint256;

    /* 15% Investors token allocation */
    uint256 public immutable Max = 3000000000 ether;

    /* Investor Roles */
    bytes32 public constant Admin = keccak256("Admin");
    bytes32 public constant Investor = keccak256("Investor");

    /* Initialization for $MetaX & Admin */
    constructor(
        address _MetaX_addr
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozen, "Investors_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract */
    bool public frozen;

    function setFrozen () public onlyOwner {
        frozen = true;
    }
    
    /* Original release for investors start @Dec 1st 2023 */
    uint256 public immutable T0 = 1701388800;

    /* 24-month linear release */
    uint256 public immutable maxClaim = 24;

    /* Monthly release */
    uint256 public immutable intervals = 30 days;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Track for accumulative allocation for investors */
    uint256 public accumAllocated;

    /* Track for accumulative tokens claimed by investors */
    uint256 public accumClaimed;

    /* Investor Info */
    struct _Investors {
        bool isInvestor; /* Investor identity verification */
        uint256 nextRelease; /* The next release time */
        uint256 max; /* Total token allocation for an investor */
        uint256 release; /* Number of tokens per release */
        uint256 alreadyClaimed; /* Number of tokens already released */
        uint256 numClaimed; /* Number of time tokens have been claimed */
        uint256 batch; /* Batch of investor list */
    }

    /* Recording investment info for an investor */
    mapping (address => _Investors) private Investors;

    /* Get Investor Info only by investors */
    function getInvestorsInfo () public view returns (_Investors memory) {
        _Investors memory Inv = Investors[msg.sender];
        require(Inv.isInvestor, "Investors_Vault: You are not an investor.");
        return Inv;
    }

    /* Get Investor Info only by admins */
    function getInvestorsInfo_admin (address _investors) public view onlyRole(Admin) returns (_Investors memory) {
        return Investors[_investors];
    }

    /* Recording investor wallet address */
    address[] private walletInvestors;

    function countInvestors () public view onlyRole(Admin) returns (uint256) {
        return walletInvestors.length;
    }

    function getWalletInvestors () public view onlyRole(Admin) returns (address[] memory) {
        return walletInvestors;
    }

    /* Initialize investor status only by owner */
    function setInvestors (address newInvestors_addr, uint256 _nextRelease, uint256 tokenMax) public onlyOwner {
        _Investors storage Inv = Investors[newInvestors_addr];
        require(!Inv.isInvestor, "Investors_Vault: This address is already an investor."); /* Check for investor identity */
        require(accumAllocated + tokenMax <= Max, "Investors_Vault: All the tokens have been allocated"); /* Check for over-allocation */
        require(_nextRelease > T0, "Investors_Vault: Investors release is not open"); /* Check for investors release open */
        uint256 _release = tokenMax.div(maxClaim); /* Divide tokan allocation by maxClaim to get tokens per release */
        Inv.isInvestor = true; /* Set investor identity */
        Inv.nextRelease = _nextRelease; /* Set the first release timestamp */
        Inv.max = tokenMax; /* Set total token allocation */
        Inv.release = _release; /* Set tokens per release */
        Inv.batch = countInvestors(); /* Set investors reference batch */
        accumAllocated += tokenMax; /* Accumulate newly allocated tokens to already allocated token pool */
        walletInvestors.push(newInvestors_addr); /* Record investors wallet reference */
    }

    /* Update investor identity only by investors themselves */
    function updateInvestors (address newInvestors_addr) public onlyRole(Investor) {
        require(Investors[msg.sender].isInvestor, "Investors_Vault: You are not an investor."); /* Check for investor identity */
        require(!Investors[newInvestors_addr].isInvestor, "Investors_Vault: You can't update to an existing investor."); /* Check for brand-new wallet */
        require(Investors[msg.sender].alreadyClaimed + Investors[msg.sender].release <= Investors[msg.sender].max, "Investors_Vault: You have claimed all your investor tokens."); /* Check for unreleased token amount */
        require(Investors[msg.sender].numClaimed < maxClaim, "Investors_Vault: You have claimed all your investors tokens"); /* Check number of unreleased time */
        Investors[newInvestors_addr].isInvestor = true; /* Update new investor identity */
        Investors[newInvestors_addr].nextRelease = Investors[msg.sender].nextRelease; /* Update new investor next release timestamp */
        Investors[newInvestors_addr].max = Investors[msg.sender].max; /* Update new investor max tokens allocation */
        Investors[newInvestors_addr].release = Investors[msg.sender].release; /* Update new investor tokens per release */
        Investors[newInvestors_addr].alreadyClaimed = Investors[msg.sender].alreadyClaimed; /* Update new investor tokens already claimed */
        Investors[newInvestors_addr].numClaimed = Investors[msg.sender].numClaimed; /* Update new investor number of time claimed */
        Investors[newInvestors_addr].batch = Investors[msg.sender].batch; /* Update new investor batch for reference */

        walletInvestors[Investors[msg.sender].batch] = newInvestors_addr; /* Update the investors wallet reference */

        delete Investors[msg.sender]; /* Delete the investor info of the original investor wallet */
        _revokeRole(Investor, msg.sender); /* Revoke the investor role of the original investor wallet */
    }

    function Claim () public {
        _Investors storage Inv = Investors[msg.sender];
        require(Inv.isInvestor, "Investors_Vault: You are not an investor"); /* Check investors identity */
        require(block.timestamp > T0, "Investors_Vault: Investors release is not open."); /* Check investor release open */
        require(block.timestamp > Inv.nextRelease, "Investors_Vault: Please wait for the next release."); /* Check next release timelock */
        require(Inv.alreadyClaimed + Inv.release <= Inv.max, "Investors_Vault: You have claimed all your investors tokens"); /* Check amount of unreleased tokens */
        require(Inv.numClaimed < maxClaim, "Investors_Vault: You have claimed all your investors tokens"); /* Check number of unreleased time */
        Inv.nextRelease = block.timestamp + intervals; /* Update next release time with 1 interval */
        Inv.alreadyClaimed += Inv.release; /* Update accumulative amount of tokens claimed */
        Inv.numClaimed ++; /* Update accumulative number of time claimed */
        accumClaimed += Inv.release; /* Update global accumulative amount of tokens claimed */
        MX.transfer(msg.sender, Inv.release); /* Claim the tokens per release */
    }

}
