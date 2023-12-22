// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.1;

import "./ArbSys.sol";
import "./AddressAliasHelper.sol";
import "./ReentrancyGuard.sol";
import "./IERC721.sol";

import "./IMushrohmBridge.sol";
import "./IPixelMushrohmBridge.sol";
import "./IPixelMushrohmERC721.sol";
import "./PixelMushrohmAccessControlled.sol";

contract PixelMushrohmBridge is IPixelMushrohmBridge, PixelMushrohmAccessControlled, ReentrancyGuard {
    /* ========== CONSTANTS ========== */

    ArbSys constant arbsys = ArbSys(address(100));

    /* ========== STATE VARIABLES ========== */

    address public l1Target;
    IPixelMushrohmERC721 public pixelMushrohm;

    /* ======== CONSTRUCTOR ======== */

    constructor(address _authority) PixelMushrohmAccessControlled(IPixelMushrohmAuthority(_authority)) {}

    /* ======== ADMIN FUNCTIONS ======== */

    function setPixelMushrohm(address _pixelMushrohm) external override onlyOwner {
        pixelMushrohm = IPixelMushrohmERC721(_pixelMushrohm);
    }

    function setL1Target(address _l1Target) external override onlyOwner {
        l1Target = _l1Target;
    }

    // Incase of a problem. Allows admin to transfer stuck NFT back to user
    function transferStuckNFT(uint256 _tokenId) external override onlyPolicy {
        IERC721(address(pixelMushrohm)).safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    /* ======== MUTABLE FUNCTIONS ======== */

    /*
    @desc:
        Function will initate a transcation to transfer the NFT from the L1 Contract to the user.

    @security :
        @impact: Critical : Should only be executed, after retrieving a PixelMushrohm from the user, that is in the range of 0-1500.
 
    @args : 
        token_id : uint256 : ID of the token, to be transfered from the L1 Contract to the user.
        
    @emits:
        L2ToL1TxCreated(withdrawalId);
    */
    function transferPixelMushrohmtoL1(uint256 _tokenId)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(_tokenId <= 1500);

        IERC721(address(pixelMushrohm)).safeTransferFrom(msg.sender, address(this), _tokenId);
        bytes memory data = abi.encodeWithSelector(IMushrohmBridge.acceptTransferFromL2.selector, _tokenId, msg.sender);
        uint256 withdrawalId = arbsys.sendTxToL1(l1Target, data);

        emit L2ToL1TxCreated(withdrawalId);
        return withdrawalId;
    }

    /*
    @desc:
        This function is the function that is targeted by the retryable ticket that is executed on L1 by the ETH Bridge Contract. 
        Will send the target_user the NFT, stored in the contract.

    @security :
        Should only be able to be called by the L1 Target Address, if not then the NFTs stored in the contract can be stolen.

    @args : 
        _tokenId : uint256 : the token id of the NFT that the L1 contract is trying to send.
        target_user : address : the address the L1 contract has been told to, send the NFT to.

    @emits:
        NFTSentToUser(tokenId, targetUser, msgSender);
    */
    function acceptTransferFromL1(uint256 _tokenId, address _targetUser) external override whenNotPaused nonReentrant {
        // Need to make sure this actually stops, hash collisions on the L2 Contract PIN: Security
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1Target),
            "Only ETH side of the bridge can transfer NFTs"
        );
        require(_tokenId <= 1500);

        if (pixelMushrohm.exists(_tokenId)) {
            IERC721(address(pixelMushrohm)).safeTransferFrom(address(this), _targetUser, _tokenId);
        } else {
            pixelMushrohm.bridgeMint(_targetUser, _tokenId);
        }

        emit NFTSentToUser(_tokenId, _targetUser, msg.sender);
    }

    /* ======== HELPER FUNCTIONS ======== */

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}

