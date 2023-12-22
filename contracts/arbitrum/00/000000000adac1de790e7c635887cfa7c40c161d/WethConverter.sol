// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {     ContractOffererInterface } from "./ContractOffererInterface.sol";

import {     SeaportInterface } from "./SeaportInterface.sol";

import { ItemType } from "./ConsiderationEnums.sol";

import {     ReceivedItem,     Schema,     SpentItem } from "./ConsiderationStructs.sol";

import {     Common_token_offset,     ratifyOrder_selector,     ReceivedItem_amount_offset,     ReceivedItem_CommonParams_size,     ReceivedItem_recipient_offset } from "./ConsiderationConstants.sol";

import { ERC165 } from "./ERC165.sol";

interface IWETH {
    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

struct Condition {
    bytes32 orderHash;
    uint256 amount;
    uint256 startTime;
    uint256 endTime;
    uint120 fractionToFulfill;
    uint120 totalSize;
}

/**
 * @title WethConverter
 * @author 0age, emo.eth, stephanm.eth
 * @notice WethConverter is a basic Seaport app for performing ETH <> WETH conversion.
 *         It will offer ETH and require an equivalent amount of WETH back,
 *         or will offer WETH and require an equivalent amount of ETH back,
 *         wrapping and unwrapping its internal balance as required to provide the requested amount.
 *         It also enables conditionally reducing the offered amount based on whether
 *         conditional listings are still available for fulfillment.
 */
contract WethConverter is ERC165, ContractOffererInterface {
    // The 4-byte error selector of `CallFailed()`
    uint256 private constant CallFailed_error_selector = 0x3204506f;

    // The 4-byte function selector of `balanceOf(address)`
    uint256 private constant Weth_BalanceOf_selector = 0x70a08231;

    // The Seaport interface used to interact with Seaport
    SeaportInterface private immutable _SEAPORT;

    // The WETH interface used to approve, wrap/unwrap, and check balances of tokens
    IWETH private immutable _WETH;

    // Mapping of account addresses to ETH deposit amounts.
    mapping(address => uint256) public balanceOf;

    /**
     * @dev Emit an event whenever an account deposits ETH into the contract.
     *
     * @param account The address of the depositor account.
     * @param amount  The amount being deposited.
     */
    event Deposit(address indexed account, uint256 amount);

    /**
     * @dev Emit an event whenever an account withdraws ETH from the contract.
     *
     * @param account The address of the withdrawing account.
     * @param amount  The amount being withdrawn.
     */
    event Withdrawal(address indexed account, uint256 amount);

    /**
     * @dev Emit an event at deployment to indicate the contract is SIP-5 compatible.
     */
    event SeaportCompatibleContractDeployed();

    /**
     * @dev Revert with an error when a function is called by an invalid caller.
     *
     * @param caller The caller of the function.
     */
    error InvalidCaller(address caller);

    /**
     * @dev Revert with an error if the total number of maximumSpentItems supplied
     *      is not 1.
     *
     * @param items The invalid number of maximumSpentItems supplied.
     */
    error InvalidTotalMaximumSpentItems(uint256 items);

    /**
     * @dev Revert with an error if the supplied maximumSpentItem is not WETH.
     *
     * @param item The invalid maximumSpentItem.
     */
    error InvalidMaximumSpentItem(SpentItem item);

    /**
     * @dev Revert with an error if the chainId is not supported.
     *
     * @param chainId The invalid chainId.
     */
    error UnsupportedChainId(uint256 chainId);

    /**
     * @dev Revert with an error if the native token transfer to Seaport fails.
     *
     * @param target The target address.
     * @param amount The amount of native tokens to transfer.
     */
    error NativeTokenTransferFailure(address target, uint256 amount);

    /**
     * @dev Revert with an error if a low-level call fails.
     */
    error CallFailed();

    /**
     * @dev Revert with an error if Conditions are invalid, or amount to offer
     *      gets scaled down to 0.
     */
    error InvalidConditions();

    constructor(address seaport) {
        // Declare a variable for the chain-dependent wrapped token address.
        address wrappedTokenAddress;

        // Set the Seaport interface with the supplied Seaport constructor argument.
        _SEAPORT = SeaportInterface(seaport);

        // Set the wrapped token address based on chain id.
        if (block.chainid == 1) {
            // Mainnet
            wrappedTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        } else if (block.chainid == 5) {
            // Goerli
            wrappedTokenAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
        } else if (block.chainid == 11155111) {
            // Sepolia
            wrappedTokenAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        } else if (block.chainid == 137) {
            // Polygon (WMATIC)
            wrappedTokenAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        } else if (block.chainid == 80001) {
            // Mumbai (WMATIC)
            wrappedTokenAddress = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        } else if (block.chainid == 10 || block.chainid == 420) {
            // Optimism and Optimism Goerli
            wrappedTokenAddress = 0x4200000000000000000000000000000000000006;
        } else if (block.chainid == 42161) {
            // Arbitrum One
            wrappedTokenAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        } else if (block.chainid == 421613) {
            // Arbitrum Goerli
            wrappedTokenAddress = 0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f;
        } else if (block.chainid == 42170) {
            // Arbitrum Nova
            wrappedTokenAddress = 0x722E8BdD2ce80A4422E880164f2079488e115365;
        } else if (block.chainid == 43114) {
            // Avalanche C-Chain (WAVAX)
            wrappedTokenAddress = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        } else if (block.chainid == 43113) {
            // Avalanche Fuji (WAVAX)
            wrappedTokenAddress = 0x1D308089a2D1Ced3f1Ce36B1FcaF815b07217be3;
        } else if (block.chainid == 56) {
            // Binance Smart Chain (WBNB)
            wrappedTokenAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        } else if (block.chainid == 97) {
            // Binance Smart Chain Testnet (WBNB)
            wrappedTokenAddress = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
        } else if (block.chainid == 100) {
            // Gnosis (WXDAI)
            wrappedTokenAddress = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
        } else if (block.chainid == 8217) {
            // Klaytn (WKLAY)
            wrappedTokenAddress = 0xfd844c2fcA5e595004b17615f891620d1cB9bBB2;
        } else if (block.chainid == 1001) {
            // Baobab (WKLAY)
            wrappedTokenAddress = 0x9330dd6713c8328a8D82b14e3f60a0f0b4cc7Bfb;
        } else if (block.chainid == 1284) {
            // Moonbeam (WGLMR)
            wrappedTokenAddress = 0xAcc15dC74880C9944775448304B263D191c6077F;
        } else if (block.chainid == 1285) {
            // Moonriver (WMOVR)
            wrappedTokenAddress = 0x98878B06940aE243284CA214f92Bb71a2b032B8A;
        } else {
            // Revert if the chain ID is not supported.
            revert UnsupportedChainId(block.chainid);
        }

        // Set the WETH interface based on WETH address.
        _WETH = IWETH(wrappedTokenAddress);

        // Set approval for Seaport to transfer the contract offerer's WETH.
        _WETH.approve(seaport, type(uint256).max);

        // Emit an event to indicate the contract is SIP-5 compatible.
        emit SeaportCompatibleContractDeployed();
    }

    /**
     * @dev Generates an order with the specified minimum and maximum spent
     *      items, and optional context (supplied as extraData).
     *
     * @custom:param fulfiller The address of the fulfiller.
     * @param minimumReceived  The minimum items that the caller must receive.
     * @param maximumSpent     The maximum items the caller is willing to spend.
     * @param context          Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration An array containing the consideration items.
     */
    function generateOrder(
        address /* fulfiller */,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    )
        external
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        // Get the Seaport address from the Seaport interface
        address seaport = address(_SEAPORT);

        // Build the order without changing state.
        (offer, consideration) = _buildOrder(
            msg.sender,
            minimumReceived,
            maximumSpent,
            context
        );

        // Get the amount from the consideration item.
        // There should only be a single consideration item on the order.
        uint256 amount = consideration[0].amount;

        // If the converter is considering native tokens, it is offering WETH.
        if (consideration[0].itemType == ItemType.NATIVE) {
            // Wrap native tokens if necessary to offer an equivalent amount of WETH.
            _wrapIfNecessary(amount);

            // If the converter is considering WETH, it is offering native tokens.
        } else {
            // Unwrap WETH if necessary to offer an equivalent amount of native tokens.
            _unwrapIfNecessary(amount);

            // Declare a boolean that indicates if the native token transfer fails.
            bool nativeTokenTransferFailed;

            // If the consideration itemType is WETH, converter needs to transfer
            // native tokens to Seaport to be spent or transferred to users.
            assembly {
                // Supply the native tokens to Seaport.
                nativeTokenTransferFailed := iszero(
                    call(gas(), seaport, amount, 0, 0, 0, 0)
                )
            }

            // Revert if the call fails.
            if (nativeTokenTransferFailed) {
                revert NativeTokenTransferFailure(seaport, amount);
            }
        }
    }

    /**
     * @dev Internal view function to build an order with the specified minimum
     *      and maximum spent items. If conditional listings (supplied as extraData)
     *      are given as context, the amount offered by the converter will be
     *      scaled down if any of the listings are unavailable.
     *
     * @param callingAccount   The address of the account that called the function.
     * @param minimumReceived  The minimum items that the caller must receive.
     * @param maximumSpent     The maximum items the caller is willing to spend.
     * @param context          Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration An array containing the consideration items.
     */
    function _buildOrder(
        address callingAccount,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context
    )
        internal
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        // Get the Seaport address from the Seaport interface
        address seaport = address(_SEAPORT);

        // Get the WETH address from the WETH interface
        address weth = address(_WETH);

        // Declare a variable to store the amount of the consideration item.
        uint256 amount;

        // Declare an error buffer.
        uint256 errorBuffer;

        assembly {
            // First check is that fulfiller is Seaport.
            errorBuffer := iszero(eq(callingAccount, seaport))
            // Next, check the length of the maximum spent array.
            errorBuffer := or(
                errorBuffer,
                shl(1, iszero(eq(maximumSpent.length, 1)))
            )
        }

        // Get the maximum spent item.
        SpentItem calldata maximumSpentItem = maximumSpent[0];

        // Declare a variable to store the consideration item type.
        ItemType considerationItemType;

        assembly {
            // Get the consideration itemType from the first word of
            // maximumSpentItem.
            considerationItemType := calldataload(maximumSpentItem)

            // If the item type is too high, or if the item is an ERC20
            // token and the token address is not WETH, the item is invalid.
            let invalidMaximumSpentItem := or(
                gt(considerationItemType, 1),
                and(
                    considerationItemType,
                    iszero(
                        eq(
                            calldataload(
                                add(maximumSpentItem, Common_token_offset)
                            ),
                            weth
                        )
                    )
                )
            )

            // Update the error buffer if maximumSpentItem is invalid.
            errorBuffer := or(errorBuffer, shl(2, invalidMaximumSpentItem))
        }

        assembly {
            // Get the consideration amount from the fourth word of
            // maximumSpentItem.
            // Note: amount offset is the same for SpentItem and ReceivedItem.
            amount := calldataload(
                add(maximumSpentItem, ReceivedItem_amount_offset)
            )
        }

        // If items are no longer available, scale down the amount to offer.
        amount = _filterUnavailable(amount, context);

        // If a native token is supplied for maximumSpent, offer WETH.
        if (considerationItemType == ItemType.NATIVE) {
            // Declare a new SpentItem for the offer.
            offer = new SpentItem[](1);

            // Set the itemType as ERC20.
            offer[0].itemType = ItemType.ERC20;

            // Set the token address as WETH.
            offer[0].token = address(_WETH);

            // Set the amount to offer.
            offer[0].amount = amount;
        } else {
            // If WETH is supplied for maximumSpent, offer native tokens.
            // Only supply minimumReceived if a minimumReceived item was provided.
            if (minimumReceived.length > 0) {
                // Declare a new SpentItem for the offer.
                // Note: itemType and token address are by default
                // NATIVE and address(0), respectively.
                offer = new SpentItem[](1);

                // Set the amount to offer.
                offer[0].amount = amount;
            }
        }

        // Check the error buffer to see if any errors were encountered.
        if (errorBuffer != 0) {
            // Check the last bit of the error buffer.
            if (errorBuffer << 255 != 0) {
                revert InvalidCaller(msg.sender);
                // Check the second to last bit of the error buffer.
            } else if (errorBuffer << 254 != 0) {
                revert InvalidTotalMaximumSpentItems(maximumSpent.length);
                // Check the third to last bit of the error buffer.
            } else if (errorBuffer << 253 != 0) {
                revert InvalidMaximumSpentItem(maximumSpent[0]);
            }
        }

        // Declare a new ReceivedItem for the consideration.
        consideration = new ReceivedItem[](1);

        // Copy the maximumSpentItem to a ReceivedItem and set as consideration.
        consideration[0] = _copySpentAsReceivedToSelf(maximumSpentItem, amount);
    }

    /**
     * @dev Enable accepting native tokens. This function could optionally use a
     *      flag set in storage as part of generateOrder, and unset as part of
     *      ratifyOrder, to reduce the risk of accidental transfers at the cost
     *      of increased overhead.
     */
    receive() external payable {}

    /**
     * @dev Deposit native tokens to the WETH converter.
     */
    function deposit() public payable {
        // Increase balance of msg.sender.
        // Wrap in unchecked block because ETH token supply won't exceed
        // 2 ** 256.
        unchecked {
            balanceOf[msg.sender] += msg.value;
        }

        // Emit a Deposit event.
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw native tokens from the WETH converter.
     */
    function withdraw(uint256 amount) public {
        // Use checked arithmetic so underflows will revert.
        balanceOf[msg.sender] -= amount;

        // Unwrap native tokens if the current internal balance is insufficient.
        _unwrapIfNecessary(amount);

        // Return the native tokens.
        assembly {
            // Send native tokens to the caller and check status of call.
            if iszero(call(gas(), caller(), amount, 0, 0, 0, 0)) {
                // Determine if reasonable amount of calldata was returned.
                if and(
                    iszero(iszero(returndatasize())),
                    lt(returndatasize(), 0xffff)
                ) {
                    // Copy the return data to memory.
                    returndatacopy(0, 0, returndatasize())

                    // Revert with the return data.
                    revert(0, returndatasize())
                }

                // Store the CallFailed error selector in memory.
                mstore(0, CallFailed_error_selector)

                // Revert with the error selector.
                revert(0x1c, 0x04)
            }
        }

        // Emit a Withdrawal event.
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Ratifies an order with the specified offer, consideration, and
     *      optional context (supplied as extraData).
     *
     * @custom:param offer         The offer items.
     * @custom:param consideration The consideration items.
     * @custom:param context       Additional context of the order.
     * @custom:param orderHashes   The hashes to ratify.
     * @custom:param contractNonce The nonce of the contract.
     *
     * @return ratifyOrderMagicValue The magic value returned by the contract
     *                               offerer.
     */
    function ratifyOrder(
        SpentItem[] calldata /* offer */,
        ReceivedItem[] calldata /* consideration */,
        bytes calldata /* context */, // encoded based on the schemaID
        bytes32[] calldata /* orderHashes */,
        uint256 /* contractNonce */
    ) external pure override returns (bytes4) {
        assembly {
            // Store the ratifyOrder function selector in memory.
            mstore(0, ratifyOrder_selector)

            // Return the selector.
            return(0x1c, 0x04)
        }
    }

    /**
     * @dev View function to preview an order generated in response to a minimum
     *      set of received items, maximum set of spent items, and context
     *      (supplied as extraData).
     *
     * @param caller           The address of the caller (e.g. Seaport).
     * @custom:param fulfiller The address of the fulfiller (e.g. the account
     *                         calling Seaport).
     * @param minimumReceived  The minimum items that the caller is willing to
     *                         receive.
     * @param maximumSpent     The maximum items caller is willing to spend.
     * @param context          Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration A tuple containing the consideration items.
     */
    function previewOrder(
        address caller,
        address /* fulfiller */,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    )
        external
        view
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        // Build the order without changing state.
        (offer, consideration) = _buildOrder(
            caller,
            minimumReceived,
            maximumSpent,
            context
        );
    }

    /**
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata()
        external
        view
        override
        returns (
            string memory name,
            Schema[] memory schemas // map to Seaport Improvement Proposal IDs
        )
    {
        // Declare an array of Schema to return.
        schemas = new Schema[](1);

        // Set the SIP schema id to 11.
        schemas[0].id = 11;

        // Set the schema metadata to an encoding of the addresses of
        // the two tokens being converted and their constant exchange rate (1:1).
        schemas[0].metadata = abi.encode(address(0), address(_WETH), 10 ** 18);

        return ("WethConverter", schemas);
    }

    /**
     * @dev Implements ERC-165 and returns true for supported interface ids.
     *
     * @param interfaceId The interface id to check for implementation.
     *
     * @return bool A boolean indicating if the interface is implemented.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC165, ContractOffererInterface) returns (bool) {
        return
            // Return true for the contract offerer interface id.
            interfaceId == type(ContractOffererInterface).interfaceId ||
            // Return true for `getSeaportMetadata()` to support SIP-5.
            interfaceId == this.getSeaportMetadata.selector ||
            /// Return true for the Seaport interface being implemented.
            interfaceId == type(SeaportInterface).interfaceId ||
            // Return true for ERC-165 interface id.
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal function to wrap native tokens to WETH if the converter's
     *      current WETH balance is insufficient.
     *
     * @param requiredAmount The amount of WETH required for the order.
     */
    function _wrapIfNecessary(uint256 requiredAmount) internal {
        // Retrieve the current wrapped balance.
        uint256 currentWrappedBalance;

        // Get the WETH address from the WETH interface.
        address weth = address(_WETH);

        assembly ("memory-safe") {
            // Save the 4-byte balanceOf selector in the first word of memory.
            mstore(0, Weth_BalanceOf_selector)

            // Save the address of this contract in the second word of memory.
            mstore(0x20, address())

            // Call balanceOf on the WETH contract and check if call was successful.
            if iszero(staticcall(gas(), weth, 0x1c, 0x24, 0, 0x20)) {
                // Store the CallFailed error selector in memory.
                mstore(0, CallFailed_error_selector)

                // Revert with the error selector.
                revert(0x1c, 0x04)
            }

            // Load the returned balance into memory.
            currentWrappedBalance := mload(0)
        }

        // Wrap if native balance is insufficient.
        if (requiredAmount > currentWrappedBalance) {
            // Retrieve the native token balance.
            uint256 currentNativeBalance = address(this).balance;

            // Derive the amount to wrap, targeting eventual 50/50 split.
            uint256 amountToWrap;

            // Wrap in unchecked block because ETH token supply won't exceed
            // 2 ** 256.
            unchecked {
                // Wrap half of (entire weth converter balance + required amount)
                // to target 50/50 split
                amountToWrap =
                    (currentNativeBalance +
                        currentWrappedBalance +
                        requiredAmount) /
                    2;
            }

            // Reduce the amount to wrap if it exceeds the native balance.
            if (amountToWrap > currentNativeBalance) {
                amountToWrap = currentNativeBalance;
            }

            assembly {
                // Perform the wrap and check if call was successful.
                if iszero(call(gas(), weth, amountToWrap, 0, 0, 0, 0)) {
                    // If call failed, save the 4-byte CallFailed selector
                    // in memory.
                    mstore(0, CallFailed_error_selector)

                    // Revert with the error selector.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /**
     * @dev Internal function to unwrap WETH to native tokens if the converter's
     *      current native balance is insufficient.
     *
     * @param requiredAmount The amount of native tokens required for the order.
     */
    function _unwrapIfNecessary(uint256 requiredAmount) internal {
        // Retrieve the native token balance.
        uint256 currentNativeBalance = address(this).balance;

        // Unwrap if native balance is insufficient.
        if (requiredAmount > currentNativeBalance) {
            // Retrieve the wrapped token balance.
            uint256 currentWrappedBalance;

            // Get WETH address from the WETH Interface.
            address weth = address(_WETH);

            assembly ("memory-safe") {
                // Save the 4-byte balanceOf selector in the first word of memory.
                mstore(0, Weth_BalanceOf_selector)

                // Save the address of this contract in the second word of memory.
                mstore(0x20, address())

                // Call balanceOf on the WETH contract and check if call
                // was successful.
                if iszero(staticcall(gas(), weth, 0x1c, 0x24, 0, 0x20)) {
                    // If call failed, save the 4-byte CallFailed selector
                    // in memory.
                    mstore(0, CallFailed_error_selector)

                    // Revert with the error selector.
                    revert(0x1c, 0x04)
                }

                // Load the returned value for the balanceOf call from memory.
                currentWrappedBalance := mload(0)
            }

            // Derive the amount to unwrap, targeting eventual 50/50 split.
            uint256 amountToUnwrap;

            unchecked {
                // Unwrap half of (entire weth converter balance + required amount)
                // to target 50/50 split
                amountToUnwrap =
                    (currentNativeBalance +
                        currentWrappedBalance +
                        requiredAmount) /
                    2;
            }

            // Reduce the amount to unwrap if it exceeds the wrapped balance.
            if (amountToUnwrap > currentWrappedBalance) {
                amountToUnwrap = currentWrappedBalance;
            }

            // Perform the unwrap.
            _WETH.withdraw(amountToUnwrap);
        }
    }

    /**
     * @dev Internal view function to reduce the amount offered by the
     *      converter if items specified in context are no longer available.
     *
     * @param amount  The original amount of the maximumSpentItem.
     * @param context The items to check for availability, encoded as Condition
     *                structs.
     *
     * @return reducedAmount The reduced amount for the converter to offer.
     */
    function _filterUnavailable(
        uint256 amount,
        bytes calldata context
    ) internal view returns (uint256 reducedAmount) {
        {
            // Declare a boolean to indicate if call should return early.
            bool returnEarly;

            // Skip if no context is supplied and some amount is supplied.
            assembly {
                returnEarly := iszero(or(context.length, iszero(amount)))
            }

            // Return amount early if no context is supplied and some amount
            // is supplied.
            if (returnEarly) {
                return amount;
            }
        }

        // First, ensure that the correct sip-6 version byte is present.
        uint256 errorBuffer = _cast(context[0] != 0x00);

        // Next, decode the context array. Note that this can be optimized for
        // calldata size (via compact encoding) and cost (via custom decoding).
        Condition[] memory conditions = abi.decode(context[1:], (Condition[]));

        // Iterate over each condition.
        uint256 totalConditions = conditions.length;
        for (uint256 i = 0; i < totalConditions; ++i) {
            // Get the condition at index i.
            Condition memory condition = conditions[i];

            // Get the condition's total size.
            uint256 conditionTotalSize = uint256(condition.totalSize);

            // Get the condition's fraction to fulfill.
            uint256 conditionTotalFilled = uint256(condition.fractionToFulfill);

            // Retrieve the order status for the condition's provided order hash.
            // Note that contract orders will always appear to be available.
            (
                ,
                // bool isValidated
                bool isCancelled,
                uint256 totalFilled,
                uint256 totalSize
            ) = _SEAPORT.getOrderStatus(condition.orderHash);

            // Derive amount to reduce based on the availability of the order.
            // Unchecked math can be used as all fill amounts are uint120 types
            // and underflow will be registered on the error buffer.
            uint256 amountToReduce;
            unchecked {
                amountToReduce =
                    (_cast(isCancelled) |
                        _cast(block.timestamp < condition.startTime) |
                        _cast(block.timestamp >= condition.endTime) |
                        (_cast(totalFilled != 0) &
                            _cast(
                                (conditionTotalFilled * totalSize) +
                                    (totalFilled * conditionTotalSize) >
                                    totalSize * conditionTotalSize
                            ))) *
                    condition.amount;

                // Set the error buffer if the amount to reduce exceeds amount.
                errorBuffer |= _cast(amountToReduce > amount);

                // Reduce the amount.
                amount -= amountToReduce;
            }
        }

        // Revert if an error was encountered or if no amount remains.
        if ((_cast(errorBuffer != 0) | _cast(amount == 0)) != 0) {
            revert InvalidConditions();
        }

        // Return the reduced amount.
        return amount;
    }

    /**
     * @dev Internal pure function to cast a `bool` value to a `uint256` value.
     *
     * @param b The `bool` value to cast.
     *
     * @return u The `uint256` value.
     */
    function _cast(bool b) internal pure returns (uint256 u) {
        assembly {
            u := b
        }
    }

    /**
     * @dev Copies a spent item from calldata and converts into a received item,
     *      applying address(this) as the recipient.
     *
     * @param spentItem The spent item.
     * @param amount    The amount on the item.
     *
     * @return receivedItem The received item.
     */
    function _copySpentAsReceivedToSelf(
        SpentItem calldata spentItem,
        uint256 amount
    ) internal view returns (ReceivedItem memory receivedItem) {
        assembly {
            // Copy the common params from spentItem
            // (itemType, token address, and identifier) to the receivedItem.
            calldatacopy(
                receivedItem,
                spentItem,
                ReceivedItem_CommonParams_size
            )

            // Store the supplied amount as the amount on the receivedItem.
            mstore(add(receivedItem, ReceivedItem_amount_offset), amount)

            // Set the weth converter as the recipient.
            mstore(add(receivedItem, ReceivedItem_recipient_offset), address())
        }
    }
}

