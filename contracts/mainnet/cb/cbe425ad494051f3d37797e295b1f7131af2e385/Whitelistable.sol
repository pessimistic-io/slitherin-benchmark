// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
import "./BPS.sol";
import "./CustomErrors.sol";
import "./LANFTUtils.sol";
import "./ERC721State.sol";
import "./ERC721LACore.sol";
import "./MerkleProof.sol";
import "./IWhitelistable.sol";
import "./WhitelistableState.sol";

abstract contract Whitelistable is IWhitelistable, ERC721LACore {
    /**
     * Create a Whitelist configuration
     * @param _editionId the edition ID
     * @param amount How many mint allowed per Whitelist spot
     * @param mintPriceInFinney Price of the whitelist mint in Finney
     * @param mintStartTS Starting time of the Whitelist mint
     * @param mintEndTS Starting time of the Whitelist mint
     * @param merkleRoot The whitelist merkle root
     *
     */
    function setWLConfig(
        uint256 _editionId,
        uint8 amount,
        uint24 mintPriceInFinney,
        uint32 mintStartTS,
        uint32 mintEndTS,
        bytes32 merkleRoot
    ) public onlyAdmin {

        WhitelistableState.WLState storage state = WhitelistableState
            ._getWhitelistableState();

        // This reverts if edition does not exist
        getEdition(_editionId);

        uint256 wlId = uint256(
            keccak256(abi.encodePacked(_editionId, amount, mintPriceInFinney))
        );

        if (state._whitelistConfig[wlId].amount != 0) {
            revert WhiteListAlreadyExists();
        }

        if (mintEndTS != 0 && mintEndTS < mintStartTS) {
            revert InvalidMintDuration();
        }

        WhitelistableState.WhitelistConfig
            memory whitelistConfig = WhitelistableState.WhitelistConfig({
                merkleRoot: merkleRoot,
                amount: amount,
                mintPriceInFinney: mintPriceInFinney,
                mintStartTS: mintStartTS,
                mintEndTS: mintEndTS
            });

        state._whitelistConfig[wlId] = whitelistConfig;
    }

    /**
     * Update a Whitelist configuration
     * @param _editionId Edition ID of the WL to be updated
     * @param _amount Amount of the WL to be updated
     * @param mintPriceInFinney Price of the WL to be updated
     * @param newAmount New Amount
     * @param newMintPriceInFinney New mint price in Finney
     * @param newMintStartTS New Mint time
     * @param newMerkleRoot New Merkle root
     * 
     * Note: When changing a single property of the WL config, 
     * make sure to also pass the value of the property that did not change.
     *
     */
    function updateWLConfig(
        uint256 _editionId,
        uint8 _amount,
        uint24 mintPriceInFinney,
        uint8 newAmount,
        uint24 newMintPriceInFinney,
        uint32 newMintStartTS,
        uint32 newMintEndTS,
        bytes32 newMerkleRoot
    ) public onlyAdmin {

        WhitelistableState.WLState storage state = WhitelistableState
            ._getWhitelistableState();

        // This reverts if edition does not exist
        getEdition(_editionId);

        uint256 wlId = uint256(
            keccak256(abi.encodePacked(_editionId, _amount, mintPriceInFinney))
        );
        WhitelistableState.WhitelistConfig memory whitelistConfig;

        // If amount or price differ, then set previous WL config key to amount 0, which effectively disable the WL
        if (_amount != newAmount || mintPriceInFinney != newMintPriceInFinney) {
            state._whitelistConfig[wlId] = WhitelistableState.WhitelistConfig({
                merkleRoot: newMerkleRoot,
                amount: 0,
                mintPriceInFinney: newMintPriceInFinney,
                mintStartTS: newMintStartTS,
                mintEndTS: newMintEndTS
            });
            wlId = uint256(
                keccak256(
                    abi.encodePacked(_editionId, newAmount, newMintPriceInFinney)
                )
            );
            state._whitelistConfig[wlId] = whitelistConfig;
        }

        if (newMintEndTS != 0 && newMintEndTS < newMintStartTS) {
            revert InvalidMintDuration();
        }
    
        whitelistConfig = WhitelistableState.WhitelistConfig({
            merkleRoot: newMerkleRoot,
            amount: newAmount,
            mintPriceInFinney: newMintPriceInFinney,
            mintStartTS: newMintStartTS,
            mintEndTS: newMintEndTS
        });

        state._whitelistConfig[wlId] = whitelistConfig;
    }

    /**
     * Whitelist mint function
     * @param _editionId the edition ID
     * @param maxAmount How many mint allowed per Whitelist spot
     * @param merkleProof the merkle proof of the minter
     * @param _quantity How many NFTs to mint
     */
    function whitelistMint(
        uint256 _editionId,
        uint8 maxAmount,
        uint24 mintPriceInFinney,
        bytes32[] calldata merkleProof,
        uint24 _quantity,
        address _recipient
    ) public payable  {
        ERC721State.ERC721LAState storage state = ERC721State
            ._getERC721LAState();
        ERC721State.Edition memory edition = getEdition(_editionId);

        // This reverts if WL does not exist (or is disabled)
        WhitelistableState.WhitelistConfig memory whitelistConfig = getWLConfig(
            _editionId,
            maxAmount,
            mintPriceInFinney
        );

        // Check for allowed mint count
        uint256 mintCountKey = uint256(
            keccak256(abi.encodePacked(_editionId, msg.sender))
        );

        if (
            state._mintedPerWallet[mintCountKey] + _quantity >
            whitelistConfig.amount
        ) {
            revert CustomErrors.MaximumMintAmountReached();
        }

        if (whitelistConfig.mintStartTS == 0 || block.timestamp < whitelistConfig.mintStartTS) {
            revert CustomErrors.MintClosed();
        }

        if (whitelistConfig.mintEndTS != 0 && block.timestamp > whitelistConfig.mintEndTS) {
            revert CustomErrors.MintClosed();
        }

        // We use msg.sender for the WL merkle root
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        if (
            !MerkleProof.verify(merkleProof, whitelistConfig.merkleRoot, leaf)
        ) {
            revert NotWhitelisted();
        }

        // Finney to Wei
        uint256 mintPriceInWei = uint256(whitelistConfig.mintPriceInFinney) *
            10e14;
        if (mintPriceInWei * _quantity > msg.value ) {
            revert CustomErrors.InsufficientFunds();
        } 

        state._mintedPerWallet[mintCountKey] += _quantity;
        uint256 firstTokenId  = _safeMint(_editionId, _quantity, _recipient);

        // Send primary royalties
        (
            address payable[] memory wallets,
            uint256[] memory primarySalePercentages
        ) = state._royaltyRegistry.primaryRoyaltyInfo(
                address(this),
                firstTokenId
            );

        uint256 nReceivers = wallets.length;

        for (uint256 i = 0; i < nReceivers; i++) {
            uint256 royalties = BPS._calculatePercentage(
                msg.value,
                primarySalePercentages[i]
            );
            (bool sent, ) = wallets[i].call{value: royalties}("");

            if (!sent) {
                revert CustomErrors.FundTransferError();
            }
        }
    }

    /**
     * Get WL config for given editionId, amout, and mintPrice.
     * Should not be used internally when trying to modify the state as it returns a memory copy of the structs
     */
    function getWLConfig(
        uint256 editionId,
        uint8 amount,
        uint24 mintPriceInFinney
    ) public view returns (WhitelistableState.WhitelistConfig memory) {
        WhitelistableState.WLState storage state = WhitelistableState
            ._getWhitelistableState();

        // This reverts if edition does not exist
        getEdition(editionId);

        uint256 wlId = uint256(
            keccak256(abi.encodePacked(editionId, amount, mintPriceInFinney))
        );
        WhitelistableState.WhitelistConfig storage whitelistConfig = state
            ._whitelistConfig[wlId];

        if (whitelistConfig.amount == 0) {
            revert CustomErrors.NotFound();
        }

        return whitelistConfig;
    }
}

