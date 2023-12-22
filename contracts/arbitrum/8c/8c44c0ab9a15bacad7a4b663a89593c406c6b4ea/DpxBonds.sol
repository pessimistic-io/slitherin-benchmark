//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";
import {Counters} from "./Counters.sol";

// Interfaces
import {IERC20Metadata as IERC20} from "./IERC20Metadata.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";

// Contracts
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {AccessControl} from "./AccessControl.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";

contract DpxBonds is
    ERC721,
    ERC721Enumerable,
    Pausable,
    AccessControl,
    ReentrancyGuard,
    ContractWhitelist
{
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    /// @dev Bond NFTs minted for deposits
    struct BondsNft {
        uint256 epoch;
        uint256 issued;
        uint256 maturityTime;
        bool redeemed;
    }

    struct Addresses {
        address usdc;
        address dpx;
        address dopexBridgoorNFT;
    }

    /// @dev Token ID counter for positions
    Counters.Counter private _tokenIdCounter;

    /// @dev Addresses of external contracts
    Addresses public addresses;

    /// @dev Current epoch
    uint256 public currentEpoch;

    /// @dev Maturity duration
    uint256 public maturityDuration = 7 days;

    /// @dev DPX precision
    uint256 public immutable dpxPrecision;

    /// @dev bond price for epoch
    mapping(uint256 => uint256) public epochBondPrice;

    /// @dev deposit amount for epoch
    mapping(uint256 => uint256) public epochDepositPerNft;

    /// @dev Discount for the each epoch
    mapping(uint256 => uint256) public maxDepositsPerEpoch;

    /// @dev Expiry for the each epoch
    mapping(uint256 => uint256) public epochExpiry;

    /// @dev total amount of usdc deposited for each epoch
    mapping(uint256 => uint256) public totalEpochDeposits;

    /// @dev Amount of usdc deposited per NFT id for each epoch
    mapping(uint256 => mapping(uint256 => uint256)) public depositsPerNftId;

    /// @dev Returns nftsState struct for nft id
    mapping(uint256 => BondsNft) public nftsState;

    // ========================================== EVENTS ==========================================
    event LogBootstrapped(
        uint256 bondPrice,
        uint256 depositPerNft,
        uint256 maxEpochDeposits,
        uint256 expiry,
        uint256 epoch
    );
    event LogMint(uint256[] usableNfts, uint256 amount, address sender);
    event LogRedeem(uint256 epoch, uint256 dpxRedeemed, address sender);
    event LogSetMaturityDuration(uint256 maturityDuration);

    constructor(
        string memory _name,
        string memory _symbol,
        Addresses memory _addresses
    ) ERC721(_name, _symbol) {
        addresses = _addresses;
        dpxPrecision = 10**IERC20(_addresses.dpx).decimals();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ========================================== ADMIN FUNCTIONS ==========================================

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by the admin
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by the admin
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the admin
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(address _contract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the admin
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(address _contract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Set the maturity duration of a bond
    /// @dev Can only be called by the admin
    /// @param _maturityDuration the maturity duration
    function setMaturityDuration(uint256 _maturityDuration)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        maturityDuration = _maturityDuration;

        emit LogSetMaturityDuration(_maturityDuration);
    }

    /**
     * @dev Bootstrap a new epoch with a certain price
     * @param bondPrice bond price for new epoch in 1e6 precision
     * @param depositPerNft usdc deposit amount per NFT
     * @param maxEpochDeposits max USDC allowed to deposit per epoch, must be (maxEpochDeposits * 10 ** 6);
     * @param expiry expiry time for the epoch
     */
    function bootstrap(
        uint256 bondPrice,
        uint256 depositPerNft,
        uint256 maxEpochDeposits,
        uint256 expiry
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whenNotPaused();
        uint256 nextEpoch = currentEpoch + 1;

        _validate(epochExpiry[currentEpoch] <= block.timestamp, 2);
        _validate(expiry > block.timestamp, 3);
        _validate(bondPrice > 0, 4);
        _validate(maxEpochDeposits > 0, 5);
        _validate(depositPerNft > 0, 6);

        IERC20(addresses.dpx).safeTransferFrom(
            msg.sender,
            address(this),
            (maxEpochDeposits * dpxPrecision) / bondPrice
        );

        epochExpiry[nextEpoch] = expiry;
        epochDepositPerNft[nextEpoch] = depositPerNft;
        maxDepositsPerEpoch[nextEpoch] = maxEpochDeposits;
        epochBondPrice[nextEpoch] = bondPrice;

        currentEpoch = nextEpoch;

        emit LogBootstrapped(
            bondPrice,
            depositPerNft,
            maxEpochDeposits,
            expiry,
            nextEpoch
        );
    }

    /// @notice Withdraw token balances from the contract (also used to emergency withdraw)
    /// @dev only callable by the owner
    /// @param tokens ERC20 tokens to withdraw
    /// @param transferNative should transfer native token
    function withdraw(address[] calldata tokens, bool transferNative)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i; i < tokens.length; ) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }

    // ========================================== CORE ==========================================

    /**
     * @dev Allows anyone to deposit erc20(usdc) during the epoch
     * @param usableNfts Amount of nfts available for deposit
     */
    function mint(uint256[] memory usableNfts) external nonReentrant {
        _isEligibleSender();
        _whenNotPaused();

        _validate(epochExpiry[currentEpoch] > block.timestamp, 1);

        uint256 amount = usableNfts.length * epochDepositPerNft[currentEpoch];

        IERC20 usdc = IERC20(addresses.usdc);
        IERC721Enumerable dopexBridgoorNFT = IERC721Enumerable(
            addresses.dopexBridgoorNFT
        );

        _validate(usableNfts.length > 0, 7);
        _validate(
            ((totalEpochDeposits[currentEpoch] + amount) <=
                maxDepositsPerEpoch[currentEpoch]),
            9
        );

        for (uint256 i; i < usableNfts.length; ) {
            _validate(dopexBridgoorNFT.ownerOf(usableNfts[i]) == msg.sender, 7);
            _validate(depositsPerNftId[currentEpoch][usableNfts[i]] == 0, 8);

            depositsPerNftId[currentEpoch][usableNfts[i]] = epochDepositPerNft[
                currentEpoch
            ];
            uint256 mintedBondsNftId = _mint(msg.sender);
            nftsState[mintedBondsNftId] = BondsNft(
                currentEpoch,
                block.timestamp,
                (block.timestamp + maturityDuration),
                false
            );

            unchecked {
                ++i;
            }
        }

        totalEpochDeposits[currentEpoch] += amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit LogMint(usableNfts, amount, msg.sender);
    }

    /**
     * @dev Mints bonds nft for deposit
     * @param to address to deposit on behalf of
     */
    function _mint(address to) internal returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev Redeems the bonds a user has
     * @param epoch epoch to redeem from
     */
    function redeem(uint256 epoch) external nonReentrant {
        _isEligibleSender();
        _whenNotPaused();

        uint256[] memory redeemableBonds = getRedeemableBonds(
            msg.sender,
            epoch
        );

        IERC20 dpx = IERC20(addresses.dpx);

        _validate(redeemableBonds.length > 0, 10);

        uint256 bondPrice = epochBondPrice[epoch]; // 1e6 precision
        uint256 dpxRedeemed;

        for (uint256 i; i < redeemableBonds.length; ) {
            nftsState[redeemableBonds[i]].redeemed = true;

            dpxRedeemed +=
                (epochDepositPerNft[epoch] * dpxPrecision) /
                bondPrice;

            _burn(redeemableBonds[i]);

            unchecked {
                ++i;
            }
        }

        dpx.safeTransfer(msg.sender, dpxRedeemed);

        emit LogRedeem(epoch, dpxRedeemed, msg.sender);
    }

    // ========================================== VIEWS/GETTERS ==========================================

    /**
     * @dev Returns an array of bond ids that were not redeemed for a selected epoch.
     * @param user address of the user
     * @param epoch epoch
     * @return array of bonds NFT ids
     */
    function getRedeemableBonds(address user, uint256 epoch)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count;
        for (uint256 i; i < balanceOf(user); ) {
            uint256 nftId = tokenOfOwnerByIndex(user, i);
            if (
                !nftsState[nftId].redeemed &&
                nftsState[nftId].epoch == epoch &&
                nftsState[nftId].maturityTime <= block.timestamp
            ) {
                count++;
            }

            unchecked {
                ++i;
            }
        }

        uint256[] memory withdrawableNftsForSelectedEpoch = new uint256[](
            count
        );

        count = 0;
        for (uint256 i = 0; i < balanceOf(user); ) {
            uint256 nftId = tokenOfOwnerByIndex(user, i);
            if (
                !nftsState[nftId].redeemed &&
                nftsState[nftId].epoch == epoch &&
                nftsState[nftId].maturityTime <= block.timestamp
            ) {
                withdrawableNftsForSelectedEpoch[count++] = nftId;
            }

            unchecked {
                i++;
            }
        }

        return withdrawableNftsForSelectedEpoch;
    }

    /**
     * @dev Returns an array of dopexBridgoorNFT ids that were not already used for deposits in the current epoch
     * @param user user address
     * @return usableNfts
     */
    function getUsableNfts(address user)
        external
        view
        returns (uint256[] memory)
    {
        uint256 count;
        IERC721Enumerable dopexBridgoorNFT = IERC721Enumerable(
            addresses.dopexBridgoorNFT
        );

        for (uint256 i; i < dopexBridgoorNFT.balanceOf(user); ) {
            if (
                getDepositsPerNftIndex(user, i) <
                epochDepositPerNft[currentEpoch]
            ) {
                count++;
            }

            unchecked {
                ++i;
            }
        }
        uint256[] memory usableNfts = new uint256[](count);
        count = 0;
        for (uint256 i; i < dopexBridgoorNFT.balanceOf(user); ) {
            if (
                getDepositsPerNftIndex(user, i) <
                epochDepositPerNft[currentEpoch]
            ) {
                usableNfts[count++] = dopexBridgoorNFT.tokenOfOwnerByIndex(
                    user,
                    i
                );
            }

            unchecked {
                ++i;
            }
        }

        return usableNfts;
    }

    /**
     * @dev Checks how much USDC was deposited per NFT by the user
     * @param user address of the user
     * @param index index of the NFT
     * @return deposit usdc deposited for NFT in current epoch
     */
    function getDepositsPerNftIndex(address user, uint256 index)
        public
        view
        returns (uint256)
    {
        return
            depositsPerNftId[currentEpoch][
                IERC721Enumerable(addresses.dopexBridgoorNFT)
                    .tokenOfOwnerByIndex(user, index)
            ];
    }

    /// @notice Function override required by solidity
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @notice Function override required by solidity
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Function to validate a condition and revert with a custom error
     * @param condition error condition
     * @param errorId the error ID
     */
    function _validate(bool condition, uint256 errorId) internal pure {
        if (!condition) {
            revert E(errorId);
        }
    }

    error E(uint256);
}

/*
ERROS:
1: Epoch not expired
2: Cannot bootstrap before current epoch's expiry
3: Expiry must be in the future
4: Bond price cannot be zero
5: maxEpochDeposits can not be zero
6: Deposit per nft not set
7: Sender does not own NFT
8: NFT already used for this epoch
9: User doesn't have a deposit
10: User doesn't have eligible bonds
*/

