// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeERC20} from "./SafeERC20.sol";

/**
 * @notice Triggers when a claim has been done for that token
 * @dev Revert when token has claimed their magic
 * @param tokenId The ID of the token that has already been claimed
 */
error AlreadyClaimed(uint256 tokenId);

/**
 * @notice Triggers when there is not enough magic to complete the claim
 * @dev Revert when balance is less than payout amount
 */
error LowBalance();

/**
 * @notice Triggers when token is not owned by the caller
 * @dev Revert when token not owned by caller
 * @param tokenId The ID of the token attempting a claim
 */
error NotOwner(uint256 tokenId);

/**
 * @notice Triggers when sending empty array to claim
 * @dev Revert when no tokens sent to claim
 */
error NothingToClaim();

/**
 * @title A claim for imbued soul holders
 * @author Neil Kistner (wyze)
 * @notice Use this contract to claim an amount of magic per Imbued Soul
 * @dev Contract used to claim magic per nft
 */
contract MagicClaim is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @notice Emits when a claim has been successful
     * @dev Emit this event on a successful claim
     * @param user The user claiming the magic
     * @param tokenId The ID of the token the claim is for
     * @param amount The amount of magic claimed
     */
    event Claimed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );

    /**
     * @notice Emits when the claimable amount is set
     * @dev Emit this when setting the claimable amount
     * @param amount The amount claimable per nft
     */
    event ClaimableSet(uint256 indexed amount);

    /**
     * @notice Emits when magic address is set
     * @dev Emit this when setting the magic contract
     * @param token The address of the magic contract
     */
    event MagicSet(address indexed token);

    /**
     * @notice Emits when nft address is set
     * @dev Emit this when setting the nft contract
     * @param nft The address of the nft contract
     */
    event NftSet(address indexed nft);

    /**
     * @notice Amount claimable per token
     * @dev Store the amount to be claimed per token
     */
    uint256 public claimable;

    /**
     * @notice Address of the magic contract
     * @dev Set to address of the magic contract
     */
    IERC20 public magic;

    /**
     * @notice Address of the nft contract to claim against
     * @dev Set to the address of the nft contract
     */
    IERC721 public nft;

    /// @dev Store balance of magic used for claims
    uint256 private balance;

    /**
     * @notice Stores if a token has claimed their magic
     * @dev Update this when a successful claim has happened for a token
     *      Mapping is as follows: tokenId => bool
     * @return True or false base on whether the token can claim or not
     */
    mapping(uint256 => bool) public claimed;

    /**
     * @dev Create the contract
     * @param nft_ Address for the nft to claim against
     * @param magic_ Address for the magic contract
     * @param claimable_ Initial amount to be claimable per nft
     */
    constructor(IERC721 nft_, IERC20 magic_, uint256 claimable_) {
        _setClaimable(claimable_);
        _setMagic(magic_);
        _setNft(nft_);
    }

    /**
     * @notice Claim your magic for your nft(s)
     * @dev Called by users to claim magic for their nft(s)
     * @param tokenIds List of token IDs to claim magic for
     */
    function claim(
        uint256[] calldata tokenIds
    ) external nonReentrant whenNotPaused {
        /// @dev Cache token claim length for savings
        uint256 length = tokenIds.length;

        /// @dev Ensure we have something to claim
        if (length == 0) {
            revert NothingToClaim();
        }

        /**
         * @dev Calculate total payout and send it after passed tokens
         *      have been verified
         */
        uint256 payout = 0;

        for (uint256 i = 0; i < length; ) {
            uint256 tokenId = tokenIds[i];

            /// @dev Ensure the user owns the token
            if (nft.ownerOf(tokenId) != _msgSender()) {
                revert NotOwner(tokenId);
            }

            /// @dev Ensure the token hasn't claimed already
            if (claimed[tokenId]) {
                revert AlreadyClaimed(tokenId);
            }

            /// @dev Add claimable amount to total payout
            payout += claimable;

            /// @dev Mark tokenId as claimed
            claimed[tokenId] = true;

            /// @dev Emit the claimed event
            emit Claimed(_msgSender(), tokenId, claimable);

            unchecked {
                i++;
            }
        }

        /// @dev Ensure we have enough balance to cover payout
        if (payout > balance) {
            revert LowBalance();
        }

        /// @dev Decrease balance by payout amount
        balance -= payout;

        magic.safeTransfer(_msgSender(), payout);
    }

    /**
     * @notice Check multiple tokens for claim eligibility
     * @dev Called by users to see if tokens have been claimed
     * @param tokenIds Tokens to check claims against
     * @return Array of booleans whether claim has been done
     */
    function claimedBatch(
        uint256[] calldata tokenIds
    ) public view returns (bool[] memory) {
        /// @dev Cache length of tokens for savings
        uint256 length = tokenIds.length;

        bool[] memory _claimed = new bool[](length);

        for (uint256 i = 0; i < length; ) {
            _claimed[i] = claimed[tokenIds[i]];

            unchecked {
                i++;
            }
        }

        return _claimed;
    }

    /**
     * @notice Deposit magic to be claimed
     * @dev Transfer magic from the sender to the contract
     * @param amount Amount of magic to transfer to the contract
     */
    function deposit(uint256 amount) external onlyOwner {
        /// @dev Increment balance by amount being deposited
        balance += amount;

        magic.safeTransferFrom(_msgSender(), address(this), amount);
    }

    /**
     * @notice Pauses ability to claim magic. All other functions still work
     * @dev Callable only by the owner to pause magic claiming
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Sets the amount claimable per nft
     * @dev Callable only by the owner to update claimable amount per nft
     * @param claimable_ Amount to be claimed per nft
     */
    function setClaimable(uint256 claimable_) external onlyOwner {
        _setClaimable(claimable_);
    }

    /**
     * @notice Sets the address of the magic contract
     * @dev Callable only by the owner to set the magic address
     * @param magic_ Address for the magic contract
     */
    function setMagic(IERC20 magic_) external onlyOwner {
        _setMagic(magic_);
    }

    /**
     * @notice Sets the address for the nft to claim against
     * @dev Callable only by the owner to set the nft address to claim against
     * @param nft_ Address for the nft contract
     */
    function setNft(IERC721 nft_) external onlyOwner {
        _setNft(nft_);
    }

    /**
     * @notice Unpauses the claiming process
     * @dev Callable only by the owner to unpause the claiming process
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Send the remaining balance back to the caller
     * @dev Callable only by the owner to get excess magic back
     */
    function withdraw() external onlyOwner {
        magic.safeTransfer(_msgSender(), balance);

        /// @dev Zero out balance after withdrawing
        balance = 0;
    }

    /**
     * @dev Sets claimable amount and emits an event
     * @param claimable_ Amount claimable per nft
     */
    function _setClaimable(uint256 claimable_) private {
        claimable = claimable_;

        emit ClaimableSet(claimable);
    }

    /**
     * @dev Sets magic contract and emits an event
     * @param magic_ Address of the magic contract
     */
    function _setMagic(IERC20 magic_) private {
        magic = magic_;

        emit MagicSet(address(magic));
    }

    /**
     * @dev Sets nft contract and emits and event
     * @param nft_ Address of the nft contract
     */
    function _setNft(IERC721 nft_) private {
        nft = nft_;

        emit NftSet(address(nft));
    }
}

