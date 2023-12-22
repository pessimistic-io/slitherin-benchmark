// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";
import {ERC165Checker} from "./ERC165Checker.sol";
import {IERC165} from "./IERC165.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import "./EnumerableSet.sol";

// @dev Solmate's ERC20 is used instead of OZ's ERC20 so we can use safeTransferLib for cheaper safeTransfers for
// ETH and ERC20 tokens
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {LSSVMPair1155} from "./LSSVMPair1155.sol";
import {LSSVMRouter} from "./LSSVMRouter.sol";
import {LSSVMPairETH} from "./LSSVMPairETH.sol";
import {LSSVMPair1155ETH} from "./LSSVMPair1155ETH.sol";
import {ICurve} from "./ICurve.sol";
import {LSSVMPairERC20} from "./LSSVMPairERC20.sol";
import {LSSVMPair1155ERC20} from "./LSSVMPair1155ERC20.sol";
import {LSSVMPairCloner} from "./LSSVMPairCloner.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";
import {LSSVMPairEnumerableETH} from "./LSSVMPairEnumerableETH.sol";
import {LSSVMPairEnumerableERC20} from "./LSSVMPairEnumerableERC20.sol";
import {LSSVMPairMissingEnumerableETH} from "./LSSVMPairMissingEnumerableETH.sol";
import {LSSVMPairMissingEnumerableERC20} from "./LSSVMPairMissingEnumerableERC20.sol";
import {LSSVMPair1155MissingEnumerableETH} from "./LSSVMPair1155MissingEnumerableETH.sol";
import {LSSVMPair1155MissingEnumerableERC20} from "./LSSVMPair1155MissingEnumerableERC20.sol";

contract LSSVMPairFactory is Ownable, ILSSVMPairFactoryLike {
    using LSSVMPairCloner for address;
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes4 private constant INTERFACE_ID_ERC721_ENUMERABLE =
        type(IERC721Enumerable).interfaceId;

    uint256 internal constant MAX_PROTOCOL_FEE = 0.10e18; // 10%, must <= 1 - MAX_FEE

    uint256 internal constant MAX_OPERATOR_PROTOCOL_FEE = 0.10e18; // 10%

    uint256 internal constant MAX_TOTAL_OPERATOR_PROTOCOL_FEE = 0.40e18; // 40%, must <= 1 - MAX_FEE - MAX_PROTOCOL_FEE

    LSSVMPairEnumerableETH public immutable enumerableETHTemplate;
    LSSVMPairMissingEnumerableETH public immutable missingEnumerableETHTemplate;
    LSSVMPairEnumerableERC20 public immutable enumerableERC20Template;
    LSSVMPairMissingEnumerableERC20
        public immutable missingEnumerableERC20Template;

    LSSVMPair1155MissingEnumerableETH
        public immutable missingEnumerable1155ETHTemplate;
    LSSVMPair1155MissingEnumerableERC20
        public immutable missingEnumerable1155ERC20Template;

    address payable public override protocolFeeRecipient;

    // Units are in base 1e18
    uint256 public override protocolFeeMultiplier;

    // nft operator
    mapping(address => mapping(address => address))
        public
        override operatorProtocolFeeRecipients;
    mapping(address => mapping(address => uint256))
        public
        override operatorProtocolFeeMultipliers;

    mapping(address => EnumerableSet.AddressSet) internal nftOperators;

    mapping(ICurve => bool) public bondingCurveAllowed;
    mapping(address => bool) public override callAllowed;
    struct RouterStatus {
        bool allowed;
        bool wasEverAllowed;
    }
    mapping(LSSVMRouter => RouterStatus) public override routerStatus;

    event NewPair(address poolAddress);
    event TokenDeposit(address poolAddress);
    event NFTDeposit(address poolAddress);
    event ProtocolFeeRecipientUpdate(address recipientAddress);
    event ProtocolFeeMultiplierUpdate(uint256 newMultiplier);
    event BondingCurveStatusUpdate(ICurve bondingCurve, bool isAllowed);
    event CallTargetStatusUpdate(address target, bool isAllowed);
    event RouterStatusUpdate(LSSVMRouter router, bool isAllowed);
    event OperatorProtocolFeeStatusUpdate(
        address nft,
        address callAddress,
        address operatorProtocolFeeRecipient,
        uint256 operatorProtocolFeeMultiplier,
        uint256 totalOperatorProtocolFeeMultipliers
    );

    constructor(
        LSSVMPairEnumerableETH _enumerableETHTemplate,
        LSSVMPairMissingEnumerableETH _missingEnumerableETHTemplate,
        LSSVMPairEnumerableERC20 _enumerableERC20Template,
        LSSVMPairMissingEnumerableERC20 _missingEnumerableERC20Template,
        LSSVMPair1155MissingEnumerableETH _missingEnumerable1155ETHTemplate,
        LSSVMPair1155MissingEnumerableERC20 _missingEnumerable1155ERC20Template,
        address payable _protocolFeeRecipient,
        uint256 _protocolFeeMultiplier
    ) {
        enumerableETHTemplate = _enumerableETHTemplate;
        missingEnumerableETHTemplate = _missingEnumerableETHTemplate;
        enumerableERC20Template = _enumerableERC20Template;
        missingEnumerableERC20Template = _missingEnumerableERC20Template;
        missingEnumerable1155ETHTemplate = _missingEnumerable1155ETHTemplate;
        missingEnumerable1155ERC20Template = _missingEnumerable1155ERC20Template;

        protocolFeeRecipient = _protocolFeeRecipient;
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
    }

    function getNftOperators(address nft)
        external
        view
        returns (address[] memory)
    {
        return nftOperators[nft].values();
    }

    function authorize(address nft, address operator) external onlyOwner {
        if (!nftOperators[nft].contains(operator)) {
            nftOperators[nft].add(operator);
        }
    }

    function unauthorize(address nft, address operator) external onlyOwner {
        delete operatorProtocolFeeRecipients[nft][operator];
        delete operatorProtocolFeeMultipliers[nft][operator];
        nftOperators[nft].remove(operator);
    }

    function setOperatorProtocolFee(
        address nft,
        address operatorProtocolFeeRecipient,
        uint256 operatorProtocolFeeMultiplier
    ) external {
        require(
            nftOperators[nft].contains(msg.sender),
            "unauthorized operator"
        );
        require(
            operatorProtocolFeeMultiplier <= MAX_OPERATOR_PROTOCOL_FEE,
            "Operator protocol fee too large"
        );

        operatorProtocolFeeRecipients[nft][
            msg.sender
        ] = operatorProtocolFeeRecipient;
        operatorProtocolFeeMultipliers[nft][
            msg.sender
        ] = operatorProtocolFeeMultiplier;
        address[] memory allOperators = nftOperators[nft].values();
        uint totalOperatorProtocolFeeMultipliers;
        for (uint i = 0; i < allOperators.length; ) {
            totalOperatorProtocolFeeMultipliers += operatorProtocolFeeMultipliers[
                nft
            ][allOperators[i]];
            unchecked {
                ++i;
            }
        }

        require(
            totalOperatorProtocolFeeMultipliers <=
                MAX_TOTAL_OPERATOR_PROTOCOL_FEE,
            "Total operator protocol fee too large"
        );
        emit OperatorProtocolFeeStatusUpdate(
            nft,
            msg.sender,
            operatorProtocolFeeRecipient,
            operatorProtocolFeeMultiplier,
            totalOperatorProtocolFeeMultipliers
        );
    }

    /**
     * External functions
     */

    /**
        @notice Creates a pair contract using EIP-1167.
        @param nft The NFT contract of the collection the pair trades
        @param bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
        @param assetRecipient The address that will receive the assets traders give during trades.
                              If set to address(0), assets will be sent to the pool address.
                              Not available to TRADE pools. 
        @param poolType TOKEN, NFT, or TRADE
        @param delta The delta value used by the bonding curve. The meaning of delta depends
        on the specific curve.
        @param fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
        @param spotPrice The initial selling spot price
        @param initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
        @return pair The new pair
     */
    struct CreatePairETHParams {
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256[] initialNFTIDs;
    }

    function createPairETH(
        CreatePairETHParams calldata params
    ) external payable returns (LSSVMPairETH pair) {
        require(
            bondingCurveAllowed[params.bondingCurve],
            "Bonding curve not whitelisted"
        );

        // Check to see if the NFT supports Enumerable to determine which template to use
        address template;
        try
            IERC165(address(params.nft)).supportsInterface(
                INTERFACE_ID_ERC721_ENUMERABLE
            )
        returns (bool isEnumerable) {
            template = isEnumerable
                ? address(enumerableETHTemplate)
                : address(missingEnumerableETHTemplate);
        } catch {
            template = address(missingEnumerableETHTemplate);
        }

        pair = LSSVMPairETH(
            payable(
                template.cloneETHPair(
                    this,
                    params.bondingCurve,
                    params.nft,
                    uint8(params.poolType)
                )
            )
        );

        _initializePairETH(
            pair,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.initialNFTIDs
        );
        emit NewPair(address(pair));
    }

    struct CreatePair1155ETHParams {
        IERC1155 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair1155.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256 nftId;
        uint256 initialNFTCount;
    }

    function createPair1155ETH(
        CreatePair1155ETHParams calldata params
    ) external payable returns (LSSVMPair1155ETH pair) {
        require(
            bondingCurveAllowed[params.bondingCurve],
            "Bonding curve not whitelisted"
        );

        // Check to see if the NFT supports Enumerable to determine which template to use
        address template = address(missingEnumerable1155ETHTemplate);

        pair = LSSVMPair1155ETH(
            payable(
                template.cloneETHPair1155(
                    this,
                    params.bondingCurve,
                    params.nft,
                    uint8(params.poolType),
                    params.nftId
                )
            )
        );

        _initializePair1155ETH(
            pair,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.nftId,
            params.initialNFTCount
        );
        emit NewPair(address(pair));
    }

    /**
        @notice Creates a pair contract using EIP-1167.
        @param _nft The NFT contract of the collection the pair trades
        @param _bondingCurve The bonding curve for the pair to price NFTs, must be whitelisted
        @param _assetRecipient The address that will receive the assets traders give during trades.
                                If set to address(0), assets will be sent to the pool address.
                                Not available to TRADE pools.
        @param _poolType TOKEN, NFT, or TRADE
        @param _delta The delta value used by the bonding curve. The meaning of delta depends
        on the specific curve.
        @param _fee The fee taken by the LP in each trade. Can only be non-zero if _poolType is Trade.
        @param _spotPrice The initial selling spot price, in ETH
        @param _initialNFTIDs The list of IDs of NFTs to transfer from the sender to the pair
        @param _initialTokenBalance The initial token balance sent from the sender to the new pair
        @return pair The new pair
     */
    struct CreateERC20PairParams {
        ERC20 token;
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256[] initialNFTIDs;
        uint256 initialTokenBalance;
    }

    function createPairERC20(CreateERC20PairParams calldata params)
        external
        returns (LSSVMPairERC20 pair)
    {
        require(
            bondingCurveAllowed[params.bondingCurve],
            "Bonding curve not whitelisted"
        );

        // Check to see if the NFT supports Enumerable to determine which template to use
        address template;
        try
            IERC165(address(params.nft)).supportsInterface(
                INTERFACE_ID_ERC721_ENUMERABLE
            )
        returns (bool isEnumerable) {
            template = isEnumerable
                ? address(enumerableERC20Template)
                : address(missingEnumerableERC20Template);
        } catch {
            template = address(missingEnumerableERC20Template);
        }

        pair = LSSVMPairERC20(
            payable(
                template.cloneERC20Pair(
                    this,
                    params.bondingCurve,
                    params.nft,
                    uint8(params.poolType),
                    params.token
                )
            )
        );

        _initializePairERC20(
            pair,
            params.token,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.initialNFTIDs,
            params.initialTokenBalance
        );
        emit NewPair(address(pair));
    }

    struct Create1155ERC20PairParams {
        ERC20 token;
        IERC1155 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256 nftId;
        uint256 initialNFTCount;
        uint256 initialTokenBalance;
    }

    function createPair1155ERC20(Create1155ERC20PairParams calldata params)
        external
        returns (LSSVMPair1155ERC20 pair)
    {
        require(
            bondingCurveAllowed[params.bondingCurve],
            "Bonding curve not whitelisted"
        );

        // Check to see if the NFT supports Enumerable to determine which template to use
        address template = address(missingEnumerable1155ERC20Template);

        pair = LSSVMPair1155ERC20(
            payable(
                template.cloneERC20Pair1155(
                    this,
                    params.bondingCurve,
                    params.nft,
                    uint8(params.poolType),
                    params.token,
                    params.nftId
                )
            )
        );

        _initializePair1155ERC20(
            pair,
            params.token,
            params.nft,
            params.assetRecipient,
            params.delta,
            params.fee,
            params.spotPrice,
            params.nftId,
            params.initialNFTCount,
            params.initialTokenBalance
        );
        emit NewPair(address(pair));
    }

    /**
        @notice Checks if an address is a LSSVMPair. Uses the fact that the pairs are EIP-1167 minimal proxies.
        @param potentialPair The address to check
        @param variant The pair variant (NFT is enumerable or not, pair uses ETH or ERC20)
        @return True if the address is the specified pair variant, false otherwise
     */
    function isPair(address potentialPair, PairVariant variant)
        public
        view
        override
        returns (bool)
    {
        if (variant == PairVariant.ENUMERABLE_ERC20) {
            return
                LSSVMPairCloner.isERC20PairClone(
                    address(this),
                    address(enumerableERC20Template),
                    potentialPair
                );
        } else if (variant == PairVariant.MISSING_ENUMERABLE_ERC20) {
            return
                LSSVMPairCloner.isERC20PairClone(
                    address(this),
                    address(missingEnumerableERC20Template),
                    potentialPair
                );
        } else if (variant == PairVariant.ENUMERABLE_ETH) {
            return
                LSSVMPairCloner.isETHPairClone(
                    address(this),
                    address(enumerableETHTemplate),
                    potentialPair
                );
        } else if (variant == PairVariant.MISSING_ENUMERABLE_ETH) {
            return
                LSSVMPairCloner.isETHPairClone(
                    address(this),
                    address(missingEnumerableETHTemplate),
                    potentialPair
                );
            ///////////////////////////////////////////////////
        } else if (variant == PairVariant.MISSING_ENUMERABLE_1155_ETH) {
            return
                LSSVMPairCloner.isETHPair1155Clone(
                    address(this),
                    address(missingEnumerable1155ETHTemplate),
                    potentialPair
                );
        } else if (variant == PairVariant.MISSING_ENUMERABLE_1155_ERC20) {
            return
                LSSVMPairCloner.isERC20Pair1155Clone(
                    address(this),
                    address(missingEnumerable1155ERC20Template),
                    potentialPair
                );
        } else {
            // invalid input
            return false;
        }
    }

    /**
        @notice Allows receiving ETH in order to receive protocol fees
     */
    receive() external payable {}

    /**
     * Admin functions
     */

    /**
        @notice Withdraws the ETH balance to the protocol fee recipient.
        Only callable by the owner.
     */
    function withdrawETHProtocolFees() external onlyOwner {
        protocolFeeRecipient.safeTransferETH(address(this).balance);
    }

    /**
        @notice Withdraws ERC20 tokens to the protocol fee recipient. Only callable by the owner.
        @param token The token to transfer
        @param amount The amount of tokens to transfer
     */
    function withdrawERC20ProtocolFees(ERC20 token, uint256 amount)
        external
        onlyOwner
    {
        token.safeTransfer(protocolFeeRecipient, amount);
    }

    /**
        @notice Changes the protocol fee recipient address. Only callable by the owner.
        @param _protocolFeeRecipient The new fee recipient
     */
    function changeProtocolFeeRecipient(address payable _protocolFeeRecipient)
        external
        onlyOwner
    {
        require(_protocolFeeRecipient != address(0), "0 address");
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdate(_protocolFeeRecipient);
    }

    /**
        @notice Changes the protocol fee multiplier. Only callable by the owner.
        @param _protocolFeeMultiplier The new fee multiplier, 18 decimals
     */
    function changeProtocolFeeMultiplier(uint256 _protocolFeeMultiplier)
        external
        onlyOwner
    {
        require(_protocolFeeMultiplier <= MAX_PROTOCOL_FEE, "Fee too large");
        protocolFeeMultiplier = _protocolFeeMultiplier;
        emit ProtocolFeeMultiplierUpdate(_protocolFeeMultiplier);
    }

    /**
        @notice Sets the whitelist status of a bonding curve contract. Only callable by the owner.
        @param bondingCurve The bonding curve contract
        @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setBondingCurveAllowed(ICurve bondingCurve, bool isAllowed)
        external
        onlyOwner
    {
        bondingCurveAllowed[bondingCurve] = isAllowed;
        emit BondingCurveStatusUpdate(bondingCurve, isAllowed);
    }

    /**
        @notice Sets the whitelist status of a contract to be called arbitrarily by a pair.
        Only callable by the owner.
        @param target The target contract
        @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setCallAllowed(address payable target, bool isAllowed)
        external
        onlyOwner
    {
        // ensure target is not / was not ever a router
        if (isAllowed) {
            require(
                !routerStatus[LSSVMRouter(target)].wasEverAllowed,
                "Can't call router"
            );
        }

        callAllowed[target] = isAllowed;
        emit CallTargetStatusUpdate(target, isAllowed);
    }

    /**
        @notice Updates the router whitelist. Only callable by the owner.
        @param _router The router
        @param isAllowed True to whitelist, false to remove from whitelist
     */
    function setRouterAllowed(LSSVMRouter _router, bool isAllowed)
        external
        onlyOwner
    {
        // ensure target is not arbitrarily callable by pairs
        if (isAllowed) {
            require(!callAllowed[address(_router)], "Can't call router");
        }
        routerStatus[_router] = RouterStatus({
            allowed: isAllowed,
            wasEverAllowed: true
        });

        emit RouterStatusUpdate(_router, isAllowed);
    }

    /**
     * Internal functions
     */

    function _initializePairETH(
        LSSVMPairETH _pair,
        IERC721 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256[] calldata _initialNFTIDs
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial ETH to pair
        payable(address(_pair)).safeTransferETH(msg.value);

        // transfer initial NFTs from sender to pair
        uint256 numNFTs = _initialNFTIDs.length;
        for (uint256 i; i < numNFTs; ) {
            _nft.safeTransferFrom(
                msg.sender,
                address(_pair),
                _initialNFTIDs[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    function _initializePair1155ETH(
        LSSVMPair1155ETH _pair,
        IERC1155 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTCount
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice, _nftId);

        // transfer initial ETH to pair
        payable(address(_pair)).safeTransferETH(msg.value);

        if (_initialNFTCount > 0) {
            // transfer initial NFTs from sender to pair
            _nft.safeTransferFrom(
                msg.sender,
                address(_pair),
                _nftId,
                _initialNFTCount,
                ""
            );
        }
        
    }

    function _initializePairERC20(
        LSSVMPairERC20 _pair,
        ERC20 _token,
        IERC721 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256[] calldata _initialNFTIDs,
        uint256 _initialTokenBalance
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice);

        // transfer initial tokens to pair
        _token.safeTransferFrom(
            msg.sender,
            address(_pair),
            _initialTokenBalance
        );

        // transfer initial NFTs from sender to pair
        uint256 numNFTs = _initialNFTIDs.length;
        for (uint256 i; i < numNFTs; ) {
            _nft.safeTransferFrom(
                msg.sender,
                address(_pair),
                _initialNFTIDs[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    function _initializePair1155ERC20(
        LSSVMPair1155ERC20 _pair,
        ERC20 _token,
        IERC1155 _nft,
        address payable _assetRecipient,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTCount,
        uint256 _initialTokenBalance
    ) internal {
        // initialize pair
        _pair.initialize(msg.sender, _assetRecipient, _delta, _fee, _spotPrice, _nftId);

        // transfer initial tokens to pair
        _token.safeTransferFrom(
            msg.sender,
            address(_pair),
            _initialTokenBalance
        );
        
        // transfer initial NFTs from sender to pair
        _nft.safeTransferFrom(
            msg.sender,
            address(_pair),
            _nftId,
            _initialNFTCount,
            ""
        );
    }

    /** 
      @dev Used to deposit NFTs into a pair after creation and emit an event for indexing (if recipient is indeed a pair)
    */
    function depositNFTs(
        IERC721 _nft,
        uint256[] calldata ids,
        address recipient
    ) external {
        // transfer NFTs from caller to recipient
        uint256 numNFTs = ids.length;
        for (uint256 i; i < numNFTs; ) {
            _nft.safeTransferFrom(msg.sender, recipient, ids[i]);

            unchecked {
                ++i;
            }
        }
        if (
            isPair(recipient, PairVariant.ENUMERABLE_ERC20) ||
            isPair(recipient, PairVariant.ENUMERABLE_ETH) ||
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_ERC20) ||
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_ETH)
        ) {
            emit NFTDeposit(recipient);
        }
    }

    /** 
      @dev Used to deposit 1155 NFTs into a pair after creation and emit an event for indexing (if recipient is indeed a pair)
    */
    function depositNFTs1155(
        IERC1155 _nft,
        uint256[] calldata ids,
        address recipient,
        uint256[] calldata counts
    ) external {
        require(ids.length == counts.length, "nft and count length must same");
        // transfer NFTs from caller to recipient
        uint256 numNFTs = ids.length;
        for (uint256 i; i < numNFTs; ) {
            _nft.safeTransferFrom(msg.sender, recipient, ids[i], counts[i], "");

            unchecked {
                ++i;
            }
        }
        if (
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_1155_ERC20) ||
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_1155_ETH)
        ) {
            emit NFTDeposit(recipient);
        }
    }

    /**
      @dev Used to deposit ERC20s into a pair after creation and emit an event for indexing (if recipient is indeed an ERC20 pair and the token matches)
     */
    function depositERC20(
        ERC20 token,
        address recipient,
        uint256 amount
    ) external {
        token.safeTransferFrom(msg.sender, recipient, amount);
        if (
            isPair(recipient, PairVariant.ENUMERABLE_ERC20) ||
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_ERC20) ||
            isPair(recipient, PairVariant.MISSING_ENUMERABLE_1155_ERC20)
        ) {
            if (token == LSSVMPairERC20(recipient).token()) {
                emit TokenDeposit(recipient);
            }
        }
    }
}

