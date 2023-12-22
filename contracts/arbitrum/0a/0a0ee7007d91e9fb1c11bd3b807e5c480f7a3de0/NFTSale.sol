// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Sale.sol";
import "./BRINFT.sol";

/**
 * @dev Contract to perform sales of BRI NFTs
 * Allows users to buy token for other tokens or coins based on predefined rates.
 * Rates differs between plans.
 */
contract NFTSale is Sale {
    using SafeERC20 for IERC20;

    uint256 constant NORMALIZED_DECIMALS = 18;
    uint256 constant ETH_DIVIDER = 10;
    uint256 constant ETH_JACKPOT_PRICE = 1 ether / 5;

    /**
     * @dev The event emitted upon burn deadline being set
     */
    event BurnDeadlineSet(uint256 deadline);

    /**
     * @dev Address to NFT collection that is being sold in the contract
     */
    BRINFT immutable nft;

    /**
     * @dev Reward Token address for burn payouts
     */
    IERC20 immutable rewardToken;

    /**
     * @dev Tokens acceptable as method of burn payment
     */
    mapping(address => bool) acceptedTokens;

    /**
     * @dev Burn deadline to which token owners can burn their NFTs
     */
    uint256 burnDeadline;

    /**
     * @dev The constructor of the contract
     *
     * @param owner_ Owner address for the contract
     * @param vault_ The vault all funds from sales will be passed to
     * @param nft_ The NFT collection that will be sold
     * @param rewardToken_ The reward token address used to distribute rewards for NFT burn
     * @param acceptedTokens_ The addresses of tokens accepted as the burn
     * @param salePlans_ All plans preconfigured with contract creation
     */
    constructor(
        address owner_,
        address payable vault_,
        BRINFT nft_,
        IERC20 rewardToken_,
        address[] memory acceptedTokens_,
        SalePlanConfiguration[] memory salePlans_
    ) Sale(owner_, vault_, salePlans_) {
        rewardToken = rewardToken_;
        nft = nft_;
        for (uint256 i = 0; i < acceptedTokens_.length;) {
            acceptedTokens[acceptedTokens_[i]] = true;
            unchecked {
                ++i;
            }
        }
        burnDeadline = 0;
    }

    /**
     * @dev Owner settable burn deadline. Can be set only once and sets how long token owners can burn their NFTs
     *
     * Note: Before setting the deadline, reward funds should be transfered to the contract
     *
     * @param deadline_ Burn deadline timestamp (in seconds)
     */
    function setBurnDeadline(uint256 deadline_) external onlyOwner {
        if (!nft.pricesSet()) revert Blocked();
        if (burnDeadline != 0) revert AlreadySet();
        burnDeadline = deadline_;
        emit BurnDeadlineSet(burnDeadline);
    }

    /**
     * @dev Method to perform NFT purchase
     *
     * @param plan_ The plan the buy refers to
     * @param amount_ Number of tokens offered for the purchase
     * @param token_ The token used to purchase
     */
    function buy(uint256 plan_, uint256 amount_, address token_) external payable {
        uint256 num_nfts = _deposit(plan_, amount_, token_);
        _retrieveFunds(_msgSender(), token_, amount_);
        nft.mint(_msgSender(), num_nfts);
    }

    /**
     * @dev The function to retrieve leftover reward tokens after burn season.
     *
     * Only the owner of the contract can do that.
     */
    function retrieveRewards() external onlyOwner {
        // slither-disable-start low-level-calls
        // slither-disable-next-line timestamp
        if (burnDeadline >= block.timestamp) revert Blocked();
        if (address(rewardToken) == address(0)) {
            // slither-disable-next-line incorrect-equality
            if (address(this).balance == 0) revert InsufficientFunds();
            (bool sent,) = owner().call{value: address(this).balance}("");
            if (!sent) revert InsufficientFunds();
        } else {
            // slither-disable-next-line incorrect-equality
            if (rewardToken.balanceOf(address(this)) == 0) revert InsufficientFunds();
            rewardToken.safeTransfer(owner(), rewardToken.balanceOf(address(this)));
        }
        // slither-disable-end low-level-calls
    }

    /**
     * @dev Method allowing token owners to burn them in exchange for 0.1 ETH
     *
     * @param tokenId_ Token ID to be burnt
     * @param paymentToken_ Token used to pay for ETH recieved for NFT burn
     */
    function burn(uint256 tokenId_, address paymentToken_) external notSuspended {
        // slither-disable-next-line timestamp
        if (burnDeadline < block.timestamp) revert Timeout();
        if (nft.ownerOf(tokenId_) != _msgSender()) revert Restricted();
        if (!acceptedTokens[paymentToken_] || nft.price(tokenId_) == 0) revert Blocked();

        // We need to denormalize the price from the original 18 digits (normalized) saved in the NFT contract
        uint256 price = nft.price(tokenId_);
        if (IERC20Metadata(paymentToken_).decimals() < NORMALIZED_DECIMALS) {
            price /= 10 ** (NORMALIZED_DECIMALS - IERC20Metadata(paymentToken_).decimals());
        }

        IERC20(paymentToken_).safeTransferFrom(_msgSender(), vault, price);
        nft.burn(tokenId_);
        if (price == ETH_JACKPOT_PRICE) {
            _transfer(_msgSender(), 1 ether);
        } else {
            _transfer(_msgSender(), 1 ether / ETH_DIVIDER);
        }
    }

    function _transfer(address to_, uint256 amount_) internal {
        // slither-disable-start low-level-calls
        if (address(rewardToken) == address(0)) {
            // slither-disable-next-line arbitrary-send-eth
            (bool sent,) = to_.call{value: amount_}("");
            if (!sent) revert InsufficientFunds();
        } else {
            rewardToken.safeTransfer(to_, amount_);
        }
        // slither-disable-end low-level-calls
    }
}

