// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";
import {OwnableWithTransferCallback} from "./OwnableWithTransferCallback.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ICurve} from "./ICurve.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {CurveErrorCodes} from "./CurveErrorCodes.sol";
import {ERC721Holder} from "./ERC721Holder.sol";

/// @title The base contract for an NFT/TOKEN AMM pair
/// @author boredGenius and 0xmons
/// @notice This implements the core swap logic from NFT to TOKEN
abstract contract LSSVMPair1155 is
    OwnableWithTransferCallback,
    ReentrancyGuard,
    ERC721Holder
{
    enum PoolType {
        TOKEN,
        NFT,
        TRADE
    }

    // 90%, must <= 1 - MAX_PROTOCOL_FEE (set in LSSVMPairFactory)
    uint256 internal constant MAX_FEE = 0.50e18;

    // The current price of the NFT
    // @dev This is generally used to mean the immediate sell price for the next marginal NFT.
    // However, this should NOT be assumed, as future bonding curves may use spotPrice in different ways.
    // Use getBuyNFTQuote and getSellNFTQuote for accurate pricing info.
    uint128 public spotPrice;

    // The parameter for the pair's bonding curve.
    // Units and meaning are bonding curve dependent.
    uint128 public delta;

    // The spread between buy and sell prices, set to be a multiplier we apply to the buy price
    // Fee is only relevant for TRADE pools
    // Units are in base 1e18
    uint96 public fee;

    // If set to 0, NFTs/tokens sent by traders during trades will be sent to the pair.
    // Otherwise, assets will be sent to the set address. Not available for TRADE pools.
    address payable public assetRecipient;

    //nftId specified by pair
    uint256 public nftId;

    // Events
    event SwapNFTInPair();
    event SwapNFTOutPair();
    event SpotPriceUpdate(uint128 newSpotPrice);
    event TokenDeposit(uint256 amount);
    event TokenWithdrawal(uint256 amount);
    event NFTWithdrawal();
    event DeltaUpdate(uint128 newDelta);
    event FeeUpdate(uint96 newFee);
    event AssetRecipientChange(address a);

    // Parameterized Errors
    error BondingCurveError(CurveErrorCodes.Error error);

    /**
      @notice Called during pair creation to set initial parameters
      @dev Only called once by factory to initialize.
      We verify this by making sure that the current owner is address(0). 
      The Ownable library we use disallows setting the owner to be address(0), so this condition
      should only be valid before the first initialize call. 
      @param _owner The owner of the pair
      @param _assetRecipient The address that will receive the TOKEN or NFT sent to this pair during swaps. NOTE: If set to address(0), they will go to the pair itself.
      @param _delta The initial delta of the bonding curve
      @param _fee The initial % fee taken, if this is a trade pair 
      @param _spotPrice The initial price to sell an asset into the pair
      @param _nftId pair nft id
     */
    function initialize(
        address _owner,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId
    ) external payable {
        require(owner() == address(0), "Initialized");
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        ICurve _bondingCurve = bondingCurve();
        PoolType _poolType = poolType();

        if ((_poolType == PoolType.TOKEN) || (_poolType == PoolType.NFT)) {
            require(_fee == 0, "Only Trade Pools can have nonzero fee");
            assetRecipient = _assetRecipient;
        } else if (_poolType == PoolType.TRADE) {
            require(_fee < MAX_FEE, "Trade fee must be less than 50%");
            require(
                _assetRecipient == address(0),
                "Trade pools can't set asset recipient"
            );
            fee = _fee;
        }
        require(_bondingCurve.validateDelta(_delta), "Invalid delta for curve");
        require(
            _bondingCurve.validateSpotPrice(_spotPrice),
            "Invalid new spot price for curve"
        );
        delta = _delta;
        spotPrice = _spotPrice;
        nftId = _nftId;
    }

    /**
     * External state-changing functions
     */

    /**
        @notice Sends token to the pair in exchange for a specific set of NFTs
        @dev To compute the amount of token to send, call bondingCurve.getBuyInfo
        This swap is meant for users who want specific IDs. Also higher chance of
        reverting if some of the specified IDs leave the pool before the swap goes through.
        @param nftIds The list of IDs of the NFTs to purchase
        @param nftIds The list of counts of the NFTs to purchase
        @param maxExpectedTokenInput The maximum acceptable cost from the sender. If the actual
        amount is greater than this value, the transaction will be reverted.
        @param nftRecipient The recipient of the NFTs
        @param isRouter True if calling from LSSVMRouter, false otherwise. Not used for
        ETH pairs.
        @param routerCaller If isRouter is true, ERC20 tokens will be transferred from this address. Not used for
        ETH pairs.
        @return inputAmount The amount of token used for purchase
     */
    function swapTokenForSpecificNFTs(
        uint256[] calldata nftIds,
        uint256[] calldata nftCounts,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable virtual nonReentrant returns (uint256 inputAmount) {
        // Store locally to remove extra calls
        ILSSVMPairFactoryLike _factory = factory();
        ICurve _bondingCurve = bondingCurve();
        // Input validation
        {
            PoolType _poolType = poolType();
            require(
                _poolType == PoolType.NFT || _poolType == PoolType.TRADE,
                "Wrong Pool type"
            );
            require((nftIds.length > 0), "Must ask for > 0 NFTs");
            require(nftIds.length == nftCounts.length, "Nft and count length must same");

            require(nftIds.length == 1, "nftIds length must be 1");
            require(nftIds[0] == nftId, "The nftId of the transaction is not specified by pair");
        }
        // Call bonding curve for pricing information
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct;

        (protocolFeeStruct, inputAmount) = _calculateBuyInfoAndUpdatePoolParams(
            nftCounts[0],
            maxExpectedTokenInput,
            _bondingCurve
        );
        
        _pullTokenInputAndPayProtocolFee(
            inputAmount,
            isRouter,
            routerCaller,
            _factory,
            protocolFeeStruct
        );

        _sendSpecificNFTsToRecipient(nft(), nftRecipient, nftIds[0], nftCounts[0]);

        _refundTokenToSender(inputAmount);

        emit SwapNFTOutPair();
    }

    /**
        @notice Sends a set of NFTs to the pair in exchange for token
        @dev To compute the amount of token to that will be received, call bondingCurve.getSellInfo.
        @param nftIds The list of IDs of the NFTs to sell to the pair
        @param nftCounts The list of counts of the NFTs to sell to the pair
        @param minExpectedTokenOutput The minimum acceptable token received by the sender. If the actual
        amount is less than this value, the transaction will be reverted.
        @param tokenRecipient The recipient of the token output
        @param isRouter True if calling from LSSVMRouter, false otherwise. Not used for
        ETH pairs.
        @param routerCaller If isRouter is true, ERC20 tokens will be transferred from this address. Not used for
        ETH pairs.
        @return outputAmount The amount of token received
     */
    function swapNFTsForToken(
        uint256[] calldata nftIds,
        uint256[] calldata nftCounts,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external virtual nonReentrant returns (uint256 outputAmount) {
        // Store locally to remove extra calls
        ILSSVMPairFactoryLike _factory = factory();
        ICurve _bondingCurve = bondingCurve();

        // Input validation
        {
            PoolType _poolType = poolType();
            require(
                _poolType == PoolType.TOKEN || _poolType == PoolType.TRADE,
                "Wrong Pool type"
            );
            require(nftIds.length > 0, "Must ask for > 0 NFTs");
            require(nftIds.length == nftCounts.length, "nft and count length must same");

            require(nftIds.length == 1, "nftIds length must be 1");
            require(nftIds[0] == nftId, "The nftId of the transaction is not specified by pair");
        }

        // Call bonding curve for pricing information
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct;
        (protocolFeeStruct, outputAmount) = _calculateSellInfoAndUpdatePoolParams(
            nftCounts[0],
            minExpectedTokenOutput,
            _bondingCurve
        );

        _sendTokenOutput(tokenRecipient, outputAmount);

        _payProtocolFeeFromPair(protocolFeeStruct);

        _takeNFTsFromSender(nft(), nftIds[0], nftCounts[0], isRouter, routerCaller);

        emit SwapNFTInPair();
    }

    /**
     * View functions
     */

    /**
        @dev Used as read function to query the bonding curve for buy pricing info
        @param numNFTs The number of NFTs to buy from the pair
     */
    function getBuyNFTQuote(
        uint256 numNFTs
        )
        external
        view
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 inputAmount,
            CurveErrorCodes.ProtocolFeeStruct  memory protocolFeeStruct
        )
    {
        uint[] memory protocolFeeMultipliers;
        address[] memory protocolFeeRecipients;
        (protocolFeeMultipliers, protocolFeeRecipients) = _getProtocolFeeMultipliersAndRecipients();
        
        (
            error,
            newSpotPrice,
            newDelta,
            inputAmount,
            protocolFeeStruct
        ) = bondingCurve().getBuyInfo(
            spotPrice,
            delta,
            numNFTs,
            fee,
            protocolFeeMultipliers
        );

        protocolFeeStruct.protocolFeeReceiver = protocolFeeRecipients;
    }

    /**
        @dev Used as read function to query the bonding curve for sell pricing info
        @param numNFTs The number of NFTs to sell to the pair
     */
    function getSellNFTQuote(uint256 numNFTs)
        external
        view
        returns (
            CurveErrorCodes.Error error,
            uint256 newSpotPrice,
            uint256 newDelta,
            uint256 outputAmount,
            CurveErrorCodes.ProtocolFeeStruct  memory protocolFeeStruct
        )
    {
        uint[] memory protocolFeeMultipliers;
        address[] memory protocolFeeRecipients;
        (protocolFeeMultipliers, protocolFeeRecipients) = _getProtocolFeeMultipliersAndRecipients();

        (
            error,
            newSpotPrice,
            newDelta,
            outputAmount,
            protocolFeeStruct
        ) = bondingCurve().getSellInfo(
            spotPrice,
            delta,
            numNFTs,
            fee,
            protocolFeeMultipliers
        );

        protocolFeeStruct.protocolFeeReceiver = protocolFeeRecipients;
    }

    /**
        @notice Returns all NFT IDs held by the pool
     */
    function getAllHeldIds() external view virtual returns (uint256[] memory);

    /**
        @notice Returns the pair's variant (NFT is enumerable or not, pair uses ETH or ERC20)
     */
    function pairVariant()
        public
        pure
        virtual
        returns (ILSSVMPairFactoryLike.PairVariant);

    function factory() public pure returns (ILSSVMPairFactoryLike _factory) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _factory := shr(
                0x60,
                calldataload(sub(calldatasize(), paramsLength))
            )
        }
    }

    /**
        @notice Returns the type of bonding curve that parameterizes the pair
     */
    function bondingCurve() public pure returns (ICurve _bondingCurve) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _bondingCurve := shr(
                0x60,
                calldataload(add(sub(calldatasize(), paramsLength), 20))
            )
        }
    }

    /**
        @notice Returns the NFT collection that parameterizes the pair
     */
    function nft() public pure returns (IERC1155 _nft) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _nft := shr(
                0x60,
                calldataload(add(sub(calldatasize(), paramsLength), 40))
            )
        }
    }

    /**
        @notice Returns the pair's type (TOKEN/NFT/TRADE)
     */
    function poolType() public pure returns (PoolType _poolType) {
        uint256 paramsLength = _immutableParamsLength();
        assembly {
            _poolType := shr(
                0xf8,
                calldataload(add(sub(calldatasize(), paramsLength), 60))
            )
        }
    }

    /**
        @notice Returns the address that assets that receives assets when a swap is done with this pair
        Can be set to another address by the owner, if set to address(0), defaults to the pair's own address
     */
    function getAssetRecipient()
        public
        view
        returns (address payable _assetRecipient)
    {
        // If it's a TRADE pool, we know the recipient is 0 (TRADE pools can't set asset recipients)
        // so just return address(this)
        if (poolType() == PoolType.TRADE) {
            return payable(address(this));
        }

        // Otherwise, we return the recipient if it's been set
        // or replace it with address(this) if it's 0
        _assetRecipient = assetRecipient;
        if (_assetRecipient == address(0)) {
            // Tokens will be transferred to address(this)
            _assetRecipient = payable(address(this));
        }
    }

    /**
     * Internal functions
     */

    /**
        @notice Calculates the amount needed to be sent into the pair for a buy and adjusts spot price or delta if necessary
        @param nftCount The amount of NFTs to purchase from the pair
        @param maxExpectedTokenInput The maximum acceptable cost from the sender. If the actual
        @param _bondingCurve _bondingCurve
        @return protocolFeeStruct protocol fee struct
        @return inputAmount The amount of tokens total tokens receive
     */
    function _calculateBuyInfoAndUpdatePoolParams(
        uint256 nftCount,
        uint256 maxExpectedTokenInput,
        ICurve _bondingCurve
    ) 
        internal 
        returns (
            CurveErrorCodes.ProtocolFeeStruct  memory protocolFeeStruct,
            uint256 inputAmount
        ) 
    {
        CurveErrorCodes.Error error;
        // Save on 2 SLOADs by caching
        uint128 currentSpotPrice = spotPrice;
        uint128 newSpotPrice;
        uint128 currentDelta = delta;
        uint128 newDelta;

        uint[] memory protocolFeeMultipliers;
        address[] memory protocolFeeRecipients;
        (protocolFeeMultipliers, protocolFeeRecipients) = _getProtocolFeeMultipliersAndRecipients();
        (
            error,
            newSpotPrice,
            newDelta,
            inputAmount,
            protocolFeeStruct
        ) = _bondingCurve.getBuyInfo(
            currentSpotPrice,
            currentDelta,
            nftCount,
            fee,
            protocolFeeMultipliers
        );

        protocolFeeStruct.protocolFeeReceiver = protocolFeeRecipients;

        // Revert if bonding curve had an error
        if (error != CurveErrorCodes.Error.OK) {
            revert BondingCurveError(error);
        }

        // Revert if input is more than expected
        require(inputAmount <= maxExpectedTokenInput, "In too many tokens");

        // Consolidate writes to save gas
        if (currentSpotPrice != newSpotPrice || currentDelta != newDelta) {
            spotPrice = newSpotPrice;
            delta = newDelta;
        }

        // Emit spot price update if it has been updated
        if (currentSpotPrice != newSpotPrice) {
            emit SpotPriceUpdate(newSpotPrice);
        }

        // Emit delta update if it has been updated
        if (currentDelta != newDelta) {
            emit DeltaUpdate(newDelta);
        }
    }

    /**
        @notice Calculates the amount needed to be sent by the pair for a sell and adjusts spot price or delta if necessary
        @param nftCount The amount of NFTs to send to the the pair
        @param minExpectedTokenOutput The minimum acceptable token received by the sender. If the actual
        @param _bondingCurve bondingCurve
        @return protocolFeeStruct protocol fee struct
        @return outputAmount The amount of tokens total tokens receive
     */
    function _calculateSellInfoAndUpdatePoolParams(
        uint256 nftCount,
        uint256 minExpectedTokenOutput,
        ICurve _bondingCurve
    ) internal returns (
            CurveErrorCodes.ProtocolFeeStruct  memory protocolFeeStruct,
            uint256 outputAmount
        ) 
    {
        CurveErrorCodes.Error error;
        // Save on 2 SLOADs by caching
        uint128 currentSpotPrice = spotPrice;
        uint128 newSpotPrice;
        uint128 currentDelta = delta;
        uint128 newDelta;

        uint[] memory protocolFeeMultipliers;
        address[] memory protocolFeeRecipients;
        (protocolFeeMultipliers, protocolFeeRecipients) = _getProtocolFeeMultipliersAndRecipients();
        (
            error,
            newSpotPrice,
            newDelta,
            outputAmount,
            protocolFeeStruct
        ) = _bondingCurve.getSellInfo(
            currentSpotPrice,
            currentDelta,
            nftCount,
            fee,
            protocolFeeMultipliers
        );

        protocolFeeStruct.protocolFeeReceiver = protocolFeeRecipients;

        // Revert if bonding curve had an error
        if (error != CurveErrorCodes.Error.OK) {
            revert BondingCurveError(error);
        }

        // Revert if output is too little
        require(
            outputAmount >= minExpectedTokenOutput,
            "Out too little tokens"
        );

        // Consolidate writes to save gas
        if (currentSpotPrice != newSpotPrice || currentDelta != newDelta) {
            spotPrice = newSpotPrice;
            delta = newDelta;
        }

        // Emit spot price update if it has been updated
        if (currentSpotPrice != newSpotPrice) {
            emit SpotPriceUpdate(newSpotPrice);
        }

        // Emit delta update if it has been updated
        if (currentDelta != newDelta) {
            emit DeltaUpdate(newDelta);
        }
    }

    /**
        @notice Pulls the token input of a trade from the trader and pays the protocol fee.
        @param inputAmount The amount of tokens to be sent
        @param isRouter Whether or not the caller is LSSVMRouter
        @param routerCaller If called from LSSVMRouter, store the original caller
        @param _factory The LSSVMPairFactory which stores LSSVMRouter allowlist info
        @param protocolFeeStruct protocol fee struct
     */
    function _pullTokenInputAndPayProtocolFee(
        uint256 inputAmount,
        bool isRouter,
        address routerCaller,
        ILSSVMPairFactoryLike _factory,
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal virtual;

    /**
        @notice Sends excess tokens back to the caller (if applicable)
        @dev We send ETH back to the caller even when called from LSSVMRouter because we do an aggregate slippage check for certain bulk swaps. (Instead of sending directly back to the router caller) 
        Excess ETH sent for one swap can then be used to help pay for the next swap.
     */
    function _refundTokenToSender(uint256 inputAmount) internal virtual;

    /**
        @notice Sends protocol fee (if it exists) back to the LSSVMPairFactory from the pair
     */
    function _payProtocolFeeFromPair(
        CurveErrorCodes.ProtocolFeeStruct memory protocolFeeStruct
    ) internal virtual;

    /**
        @notice Sends tokens to a recipient
        @param tokenRecipient The address receiving the tokens
        @param outputAmount The amount of tokens to send
     */
    function _sendTokenOutput(
        address payable tokenRecipient,
        uint256 outputAmount
    ) internal virtual;



    /**
        @notice Sends specific NFTs to a recipient address
        @dev Even though we specify the NFT address here, this internal function is only 
        used to send NFTs associated with this specific pool.
        @param _nft The address of the NFT to send
        @param nftRecipient The receiving address for the NFTs
        @param nftId The specific ID of NFT to send  
        @param nftCount The specific count of NFT to send  
     */
    function _sendSpecificNFTsToRecipient(
        IERC1155 _nft,
        address nftRecipient,
        uint256 nftId,
        uint256 nftCount
    ) internal virtual;

    /**
        @notice Takes NFTs from the caller and sends them into the pair's asset recipient
        @dev This is used by the LSSVMPair's swapNFTForToken function. 
        @param _nft The NFT collection to take from
        @param nftId The specific NFT IDs to take
        @param nftCount The specific NFT counts to take
        @param isRouter True if calling from LSSVMRouter, false otherwise. Not used for
        ETH pairs.
        @param routerCaller If isRouter is true, ERC20 tokens will be transferred from this address. Not used for
        ETH pairs.
     */
    function _takeNFTsFromSender(
        IERC1155 _nft,
        uint256 nftId,
        uint256 nftCount,
        bool isRouter,
        address routerCaller
    ) internal virtual {
        {
            address _assetRecipient = getAssetRecipient();

            if (isRouter) {
                // Verify if router is allowed
                LSSVMRouter router = LSSVMRouter(payable(msg.sender));
                (bool routerAllowed, ) = factory().routerStatus(router);
                require(routerAllowed, "Not router");

                // Call router to pull NFTs
                // If more than 1 NFT is being transfered, we can do a balance check instead of an ownership check, as pools are indifferent between NFTs from the same collection
                uint beforeBalance = _nft.balanceOf(
                    _assetRecipient,
                    nftId
                );

                router.pairTransfer1155NFTFrom(
                    _nft,
                    routerCaller,
                    _assetRecipient,
                    nftId,
                    nftCount,
                    pairVariant()
                );

                require(
                    (_nft.balanceOf(_assetRecipient, nftId) -
                        beforeBalance) == nftCount,
                    "NFT not transferred"
                );

                    
            } else {
                // Pull NFTs directly from sender
                _nft.safeTransferFrom(
                    msg.sender,
                    _assetRecipient,
                    nftId,
                    nftCount,
                    ""
                );
            }
        }
    }

    /**
        @dev Used internally to grab pair parameters from calldata, see LSSVMPairCloner for technical details
     */
    function _immutableParamsLength() internal pure virtual returns (uint256);

    /**
     * Owner functions
     */

    /**
        @notice Rescues a specified set of NFTs owned by the pair to the owner address. (onlyOwnable modifier is in the implemented function)
        @dev If the NFT is the pair's collection, we also remove it from the id tracking (if the NFT is missing enumerable).
        @param a The NFT to transfer
        @param nftIds The list of IDs of the NFTs to send to the owner
     */
    function withdrawERC721(IERC721 a, uint256[] calldata nftIds)
        external
        onlyOwner
    {
        {
            uint256 numNFTs = nftIds.length;
            for (uint256 i; i < numNFTs; ) {
                a.safeTransferFrom(address(this), msg.sender, nftIds[i]);

                unchecked {
                    ++i;
                }
            }
        }
    }

    /**
        @notice Rescues ERC20 tokens from the pair to the owner. Only callable by the owner (onlyOwnable modifier is in the implemented function).
        @param a The token to transfer
        @param amount The amount of tokens to send to the owner
     */
    function withdrawERC20(ERC20 a, uint256 amount) external virtual;

    /**
        @notice Rescues ERC1155 tokens from the pair to the owner. Only callable by the owner.
        @param a The NFT to transfer
        @param ids The NFT ids to transfer
        @param amounts The amounts of each id to transfer
     */
    function withdrawERC1155(
        IERC1155 a,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external virtual;

    /**
        @notice Updates the selling spot price. Only callable by the owner.
        @param newSpotPrice The new selling spot price value, in Token
     */
    function changeSpotPrice(uint128 newSpotPrice) external onlyOwner {
        ICurve _bondingCurve = bondingCurve();
        require(
            _bondingCurve.validateSpotPrice(newSpotPrice),
            "Invalid new spot price for curve"
        );
        if (spotPrice != newSpotPrice) {
            spotPrice = newSpotPrice;
            emit SpotPriceUpdate(newSpotPrice);
        }
    }

    /**
        @notice Updates the delta parameter. Only callable by the owner.
        @param newDelta The new delta parameter
     */
    function changeDelta(uint128 newDelta) external onlyOwner {
        ICurve _bondingCurve = bondingCurve();
        require(
            _bondingCurve.validateDelta(newDelta),
            "Invalid delta for curve"
        );
        if (delta != newDelta) {
            delta = newDelta;
            emit DeltaUpdate(newDelta);
        }
    }

    /**
        @notice Updates the fee taken by the LP. Only callable by the owner.
        Only callable if the pool is a Trade pool. Reverts if the fee is >=
        MAX_FEE.
        @param newFee The new LP fee percentage, 18 decimals
     */
    function changeFee(uint96 newFee) external onlyOwner {
        PoolType _poolType = poolType();
        require(_poolType == PoolType.TRADE, "Only for Trade pools");
        require(newFee < MAX_FEE, "Trade fee must be less than 50%");
        if (fee != newFee) {
            fee = newFee;
            emit FeeUpdate(newFee);
        }
    }

    /**
        @notice Changes the address that will receive assets received from
        trades. Only callable by the owner.
        @param newRecipient The new asset recipient
     */
    function changeAssetRecipient(address payable newRecipient)
        external
        onlyOwner
    {
        PoolType _poolType = poolType();
        require(_poolType != PoolType.TRADE, "Not for Trade pools");
        if (assetRecipient != newRecipient) {
            assetRecipient = newRecipient;
            emit AssetRecipientChange(newRecipient);
        }
    }

    /**
        @notice Allows the pair to make arbitrary external calls to contracts
        whitelisted by the protocol. Only callable by the owner.
        @param target The contract to call
        @param data The calldata to pass to the contract
     */
    function call(address payable target, bytes calldata data)
        external
        onlyOwner
    {
        ILSSVMPairFactoryLike _factory = factory();
        require(_factory.callAllowed(target), "Target must be whitelisted");
        (bool result, ) = target.call{value: 0}(data);
        require(result, "Call failed");
    }

    /**
        @notice Allows owner to batch multiple calls, forked from: https://github.com/boringcrypto/BoringSolidity/blob/master/contracts/BoringBatchable.sol 
        @dev Intended for withdrawing/altering pool pricing in one tx, only callable by owner, cannot change owner
        @param calls The calldata for each call to make
        @param revertOnFail Whether or not to revert the entire tx if any of the calls fail
     */
    function multicall(bytes[] calldata calls, bool revertOnFail)
        external
        onlyOwner
    {
        for (uint256 i; i < calls.length; ) {
            (bool success, bytes memory result) = address(this).delegatecall(
                calls[i]
            );
            if (!success && revertOnFail) {
                revert(_getRevertMsg(result));
            }

            unchecked {
                ++i;
            }
        }

        // Prevent multicall from malicious frontend sneaking in ownership change
        require(
            owner() == msg.sender,
            "Ownership cannot be changed in multicall"
        );
    }

    /**
      @param _returnData The data returned from a multicall result
      @dev Used to grab the revert string from the underlying call
     */
    function _getRevertMsg(bytes memory _returnData)
        internal
        pure
        returns (string memory)
    {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    function _getProtocolFeeMultipliersAndRecipients()
        internal
        view
        returns (
            uint[] memory protocolFeeMultipliers,
            address[] memory protocolFeeRecipients
        )
    {
        ILSSVMPairFactoryLike _factory = factory();
        // 1  calculate totalProtocolFeeMultiplier
        address[] memory nftOperators = _factory.getNftOperators(address(nft()));

        protocolFeeMultipliers = new uint[](nftOperators.length + 1);
        protocolFeeRecipients = new address[](nftOperators.length + 1);

        for (uint256 i = 0; i < nftOperators.length; ) {
            protocolFeeMultipliers[i] = _factory.operatorProtocolFeeMultipliers(
                address(nft()),
                nftOperators[i]
            );
            protocolFeeRecipients[i] = _factory.operatorProtocolFeeRecipients(
                address(nft()),
                nftOperators[i]
            );

            unchecked {
                ++i;
            }
        }

        protocolFeeMultipliers[protocolFeeMultipliers.length - 1] = _factory.protocolFeeMultiplier();
        protocolFeeRecipients[protocolFeeRecipients.length - 1] = address(_factory);
    }
}

