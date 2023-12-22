// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Advisors_Vault is AccessControl, Ownable {
    using SafeMath for uint256;

    /* 5% Advisors token allocation */
    uint256 public immutable Max = 1000000000 ether;

    /* Advisor Roles */
    bytes32 public constant Admin = keccak256("Admin");
    bytes32 public constant Advisor = keccak256("Advisor");

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
        require(!frozen, "Advisors_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract */
    bool public frozen;

    function setFrozen () public onlyOwner {
        frozen = true;
    }
    
    /* Original release for Advisors start @Dec 1st 2023 */
    uint256 public immutable T0 = 1701388800;

    /* 36-month linear release */
    uint256 public immutable maxClaim = 36;

    /* Monthly release */
    uint256 public immutable intervals = 30 days;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Track for accumulative allocation for Advisors */
    uint256 public accumAllocated;

    /* Track for accumulative tokens claimed by Advisors */
    uint256 public accumClaimed;

    /* Advisor Info */
    struct _Advisors {
        bool isAdvisor; /* Advisor identity verification */
        uint256 nextRelease; /* The next release time */
        uint256 max; /* Total token allocation for an Advisor */
        uint256 release; /* Number of tokens per release */
        uint256 alreadyClaimed; /* Number of tokens already released */
        uint256 numClaimed; /* Number of time tokens have been claimed */
        uint256 batch; /* Batch of Advisor list */
    }

    /* Recording Advisor info for an Advisor */
    mapping (address => _Advisors) private Advisors;

    /* Get Advisor Info only by Advisors */
    function getAdvisorsInfo () public view returns (_Advisors memory) {
        _Advisors memory Adv = Advisors[msg.sender];
        require(Adv.isAdvisor, "Advisors_Vault: You are not an Advisor.");
        return Adv;
    }

    /* Get Advisor Info only by admins */
    function getAdvisorsInfo_admin (address _advisors) public view onlyRole(Admin) returns (_Advisors memory) {
        return Advisors[_advisors];
    }

    /* Recording Advisor wallet address */
    address[] private walletAdvisors;

    function countAdvisors () public view onlyRole(Admin) returns (uint256) {
        return walletAdvisors.length;
    }

    function getWalletAdvisors () public view onlyRole(Admin) returns (address[] memory) {
        return walletAdvisors;
    }

    /* Initialize Advisor status only by owner */
    function setAdvisors (address newAdvisors_addr, uint256 _nextRelease, uint256 tokenMax) public onlyOwner {
        _Advisors storage Adv = Advisors[newAdvisors_addr];
        require(!Adv.isAdvisor, "Advisors_Vault: This address is already an Advisor."); /* Check for Advisor identity */
        require(accumAllocated + tokenMax <= Max, "Advisors_Vault: All the tokens have been allocated"); /* Check for over-allocation */
        require(_nextRelease > T0, "Advisors_Vault: Advisors release is not open."); /* Check for advisors release open */
        uint256 _release = tokenMax.div(maxClaim); /* Divide tokan allocation by maxClaim to get tokens per release */
        Adv.isAdvisor = true; /* Set Advisor identity */
        Adv.nextRelease = _nextRelease; /* Set the first release timestamp */
        Adv.max = tokenMax; /* Set total token allocation */
        Adv.release = _release; /* Set tokens per release */
        Adv.batch = countAdvisors(); /* Set Advisors reference batch */
        accumAllocated += tokenMax; /* Accumulate newly allocated tokens to already allocated token pool */
        walletAdvisors.push(newAdvisors_addr); /* Record Advisors wallet reference */
    }

    /* Update Advisor identity only by Advisors themselves */
    function updateAdvisors (address newAdvisors_addr) public onlyRole(Advisor) {
        require(Advisors[msg.sender].isAdvisor, "Advisors_Vault: You are not an Advisor."); /* Check for Advisor identity */
        require(!Advisors[newAdvisors_addr].isAdvisor, "Advisors_Vault: You can't update to an existing Advisor."); /* Check for brand-new wallet */
        require(Advisors[msg.sender].alreadyClaimed + Advisors[msg.sender].release <= Advisors[msg.sender].max, "Advisors_Vault: You have claimed all your Advisor tokens."); /* Check for unreleased token amount */
        require(Advisors[msg.sender].numClaimed < maxClaim, "Advisors_Vault: You have claimed all your Advisors tokens"); /* Check number of unreleased time */
        Advisors[newAdvisors_addr].isAdvisor = true; /* Update new Advisor identity */
        Advisors[newAdvisors_addr].nextRelease = Advisors[msg.sender].nextRelease; /* Update new Advisor next release timestamp */
        Advisors[newAdvisors_addr].max = Advisors[msg.sender].max; /* Update new Advisor max tokens allocation */
        Advisors[newAdvisors_addr].release = Advisors[msg.sender].release; /* Update new Advisor tokens per release */
        Advisors[newAdvisors_addr].alreadyClaimed = Advisors[msg.sender].alreadyClaimed; /* Update new Advisor tokens already claimed */
        Advisors[newAdvisors_addr].numClaimed = Advisors[msg.sender].numClaimed; /* Update new Advisor number of time claimed */
        Advisors[newAdvisors_addr].batch = Advisors[msg.sender].batch; /* Update new Advisor batch for reference */

        walletAdvisors[Advisors[msg.sender].batch] = newAdvisors_addr; /* Update the Advisors wallet reference */

        delete Advisors[msg.sender]; /* Delete the Advisor info of the original Advisor wallet */
        _revokeRole(Advisor, msg.sender); /* Revoke the Advisor role of the original Advisor wallet */
    }

    function Claim () public {
        _Advisors storage Adv = Advisors[msg.sender];
        require(Adv.isAdvisor, "Advisors_Vault: You are not an Advisor"); /* Check Advisors identity */
        require(block.timestamp > T0, "Advisors_Vault: Advisors release is not open."); /* Check Advisor release open */
        require(block.timestamp > Adv.nextRelease, "Advisors_Vault: Please wait for the next release."); /* Check next release timelock */
        require(Adv.alreadyClaimed + Adv.release <= Adv.max, "Advisors_Vault: You have claimed all your Advisors tokens"); /* Check amount of unreleased tokens */
        require(Adv.numClaimed < maxClaim, "Advisors_Vault: You have claimed all your Advisors tokens"); /* Check number of unreleased time */
        Adv.nextRelease = block.timestamp + intervals; /* Update next release time with 1 interval */
        Adv.alreadyClaimed += Adv.release; /* Update accumulative amount of tokens claimed */
        Adv.numClaimed ++; /* Update accumulative number of time claimed */
        accumClaimed += Adv.release; /* Update global accumulative amount of tokens claimed */
        MX.transfer(msg.sender, Adv.release); /* Claim the tokens per release */
    }

}
