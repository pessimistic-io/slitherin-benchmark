// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IMetaX.sol";
import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract EarlyBirdBuilder is AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    constructor() {  
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** Smart Contracts Preset **/
    /* MetaX */
    address public MetaX_Addr;

    IERC20 public MX;

    function setMetaX (address _MetaX_Addr) public onlyOwner {
        MetaX_Addr = _MetaX_Addr;
        MX = IERC20(_MetaX_Addr);
    }

    /* XPower of BlackHole */
    address public BlackHole_Addr;

    IMetaX public BH;

    function setBlackHole (address _BlackHole_Addr) public onlyOwner {
        BlackHole_Addr = _BlackHole_Addr;
        BH = IMetaX(_BlackHole_Addr);
    }

    /* Excess Claimable Builder */
    address public ExcessClaimableBuilder;

    IMetaX public ECB;

    function setExcessClaimableBuilder (address _ExcessClaimableBuilder) public onlyOwner {
        ExcessClaimableBuilder = _ExcessClaimableBuilder;
        ECB = IMetaX(_ExcessClaimableBuilder);
    }

/** Claiming Rules **/
    uint256 public beginTime = 1693526400; /* 2023/09/01 00:00 UTC */

    uint256 public deadline_Ini = 1696118400; /* 2023/09/30 24:00 UTC */

    uint256 public deadline_Claim = 1735689600; /* 2024/12/31 24:00 UTC */

/** Early Bird Initialization **/
    /* Verify - Initialization */
    bytes32 public merkleRoot_Ini;

    function setRoot_Ini (bytes32 _merkleRoot_Ini) external onlyRole(Admin) {
        merkleRoot_Ini = _merkleRoot_Ini;
    }

    function verify_Ini (
        uint256 _tokenId_BH,
        uint256 EarlyBirdTokens,
        uint256 EarlyBirdExcess,
        uint256 EarlyBirdPOSW,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory POSW_SocialPlatform,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _tokenId_BH, EarlyBirdTokens, EarlyBirdExcess, EarlyBirdPOSW, Id_SocialPlatform, POSW_SocialPlatform));
        return MerkleProof.verify(merkleProof, merkleRoot_Ini, leaf);
    }

    /* Early Bird Recording */
    struct _EarlyBirdToken {
        uint256 tokenId_BH;
        uint256 tokenMax;
        uint256 tokenClaimed;
        uint256 intervals;
        uint256 recentClaimed;
        uint256 maxClaimed;
        uint256 numberClaimed;
    }

    mapping (address => _EarlyBirdToken) public EarlyBirdToken;

    uint256 public maxClaimed = 12;

    uint256 public intervals = 7 days;

    /* Initialize Early Bird */
    mapping (uint256 => bool) public BHalreadyInitialized;

    uint256 public extraTokens = 136301468 ether;

    function Initialize (
        uint256 _tokenId_BH,
        uint256 EarlyBirdTokens,
        uint256 EarlyBirdExcess,
        uint256 EarlyBirdPOSW,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory POSW_SocialPlatform,
        bytes32[] calldata merkleProof
    ) public {
        require(block.timestamp >= beginTime && block.timestamp <= deadline_Ini, "Early Bird: Initialization needs to be finished within Sept 2023.");
        require(!BHalreadyInitialized[_tokenId_BH], "Early Bird: Your BlackHole SBT has already initialized.");
        require(EarlyBirdToken[msg.sender].tokenId_BH == 0, "Early Bird: Your wallet has already initialized.");
        require(verify_Ini(_tokenId_BH, EarlyBirdTokens, EarlyBirdExcess, EarlyBirdPOSW, Id_SocialPlatform, POSW_SocialPlatform, merkleProof), "Early Bird: Incorrect Early Bird rewards.");
        uint256 totalExcess = EarlyBirdExcess + ECB._getExcess(_tokenId_BH);
        ECB._setExcess(_tokenId_BH, totalExcess);
        BH.addPOSW_Builder(_tokenId_BH, EarlyBirdPOSW, Id_SocialPlatform, POSW_SocialPlatform);
        BHalreadyInitialized[_tokenId_BH] = true;
        EarlyBirdToken[msg.sender] = _EarlyBirdToken(_tokenId_BH, EarlyBirdTokens, 0, 7 days, 0, 12, 0);
        extraTokens -= EarlyBirdTokens;
    }

/** Early Bird Claim **/
    /* Claim */
    function Claim_Builder () public {
        uint256 tokens = EarlyBirdToken[msg.sender].tokenMax / EarlyBirdToken[msg.sender].maxClaimed;
        require(block.timestamp >= EarlyBirdToken[msg.sender].recentClaimed + intervals, "Early Bird Builder: Please wait for next release.");
        require(EarlyBirdToken[msg.sender].tokenClaimed + tokens < EarlyBirdToken[msg.sender].tokenMax, "Early Bird Builder: You have claimed all your early bird tokens.");
        require(EarlyBirdToken[msg.sender].numberClaimed < EarlyBirdToken[msg.sender].maxClaimed, "Early Bird Builder: You have claimed all your early bird tokens.");
        MX.transfer(msg.sender, tokens);
        EarlyBirdToken[msg.sender].tokenClaimed += tokens;
        EarlyBirdToken[msg.sender].numberClaimed ++;
        EarlyBirdToken[msg.sender].recentClaimed = block.timestamp;
        emit EarlyBirdRecord(msg.sender, tokens, block.timestamp);
    }

    event EarlyBirdRecord(address user, uint256 tokens, uint256 time);

/** Burn Extra **/
    bool public alreadyBurnt;

    function burnExtra () public onlyOwner {
        require(!alreadyBurnt, "Early Bird: The extra tokens have already been burnt.");
        require(block.timestamp > deadline_Ini, "Early Bird: Initialization period is not over.");
        IMetaX(MetaX_Addr).Burn(address(this), extraTokens);
        alreadyBurnt = true;
    }

    function burnRemaining () public onlyOwner {
        require(block.timestamp > deadline_Claim, "Early Bird: Claiming period is not over.");
        IMetaX(MetaX_Addr).Burn(address(this), MX.balanceOf(address(this)));
    }
}
