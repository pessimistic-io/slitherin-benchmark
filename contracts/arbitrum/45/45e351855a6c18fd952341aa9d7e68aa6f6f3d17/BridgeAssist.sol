// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import "./AccessControl.sol";
import "./ECDSA.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Strings.sol";
import "./EnumerableSet.sol";
import "./EIP712.sol";

/// @title BridgeAssist
/// @author gotbit
/// @dev Contract for sending tokens between chains assisted by a relayer,
/// supporting fee on send/fulfill, supporting multiple chains including
/// non-EVM blockchains, with a configurable limit per send and exchange rate
/// between chains.
contract BridgeAssist is AccessControl, Pausable, EIP712 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct Transaction {
        uint256 amount;
        uint256 timestamp;
        address fromUser;
        string toUser; // can be a solana address
        string fromChain;
        string toChain;
        uint256 nonce;
    }

    struct FulfillTx {
        uint256 amount;
        string fromUser; // can be a solana address
        address toUser;
        string fromChain;
        uint256 nonce;
    }

    bytes32 public constant FULFILL_TX_TYPEHASH =
        keccak256(
            'FulfillTx(uint256 amount,string fromUser,address toUser,string fromChain,uint256 nonce)'
        );
    bytes32 public constant RELAYER_ROLE = keccak256('RELAYER_ROLE');
    uint256 public constant FEE_DENOMINATOR = 10000;
    bytes32 public immutable CURRENT_CHAIN_B32;
    IERC20 public immutable TOKEN;

    address public feeWallet;
    uint256 public limitPerSend; // maximum amount of tokens that can be sent in 1 tx
    uint256 public feeSend;
    uint256 public feeFulfill;
    uint256 public nonce;

    mapping(address => Transaction[]) public transactions;
    mapping(string => mapping(string => mapping(uint256 => bool))) public fulfilled;
    mapping(bytes32 => uint256) public exchangeRateFrom;

    EnumerableSet.Bytes32Set private availableChainsToSend;

    event SentTokens(
        address fromUser,
        string indexed toUser,
        string fromChain,
        string toChain,
        uint256 amount,
        uint256 exchangeRate
    );

    event FulfilledTokens(
        string indexed fromUser,
        address indexed toUser,
        string fromChain,
        string toChain,
        uint256 amount,
        uint256 exchangeRate
    );

    constructor(
        IERC20 token,
        uint256 limitPerSend_,
        address feeWallet_,
        uint256 feeSend_,
        uint256 feeFulfill_,
        address owner
    ) EIP712('BridgeAssist', '1.0') {
        require(address(token) != address(0), 'Token is zero address');
        require(feeWallet_ != address(0), 'Fee wallet is zero address');
        require(feeSend_ < FEE_DENOMINATOR, 'Fee send is too high');
        require(feeFulfill_ < FEE_DENOMINATOR, 'Fee fulfill is too high');
        require(owner != address(0), 'Owner is zero address');
        
        TOKEN = token;
        limitPerSend = limitPerSend_;
        feeWallet = feeWallet_;
        feeSend = feeSend_;
        feeFulfill = feeFulfill_;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        CURRENT_CHAIN_B32 = bytes32(
            bytes.concat('evm.', bytes(Strings.toString(uint256(block.chainid))))
        );
    }

    /// @dev sends the user's tokens to another chain
    /// @param amount amount of tokens being sent
    /// @param toUser address of user on target chain
    /// @param toChain name of target chain (e.g. "evm.97", "sol.mainnet-beta")
    function send(
        uint256 amount,
        string memory toUser, // marked as memory to prevent "stack too deep"
        string calldata toChain
    ) external whenNotPaused {
        require(amount != 0, 'Amount = 0');
        require(amount <= limitPerSend, 'Amount is more than limit');
        require(bytes(toUser).length != 0, 'Field toUser is empty');
        require(isSupportedChain(toChain), 'Chain is not supported');

        uint256 exchangeRate = exchangeRateFrom[bytes32(bytes(toChain))];
        require(amount % exchangeRate == 0, 'Amount is not divisible by exchange rate');
        require(amount / exchangeRate >= FEE_DENOMINATOR, 'amount < fee denominator');

        {
          uint256 balanceBefore = TOKEN.balanceOf(address(this));
          _receiveTokens(msg.sender, amount);
          uint256 balanceAfter = TOKEN.balanceOf(address(this));

          require(balanceAfter - balanceBefore == amount, 'bad token');
        }

        uint256 currentFee = (amount * feeSend) / FEE_DENOMINATOR;
        if (currentFee != 0) _dispenseTokens(feeWallet, currentFee);

        transactions[msg.sender].push(
            Transaction({
                fromUser: msg.sender,
                toUser: toUser,
                amount: (amount - currentFee) / exchangeRate,
                // No logic of the system relies on this timestamp,
                // it's only needed for displaying on the frontend
                timestamp: block.timestamp,
                fromChain: CURRENT_CHAIN(),
                toChain: toChain,
                nonce: nonce++
            })
        );
        emit SentTokens(
            msg.sender,
            toUser,
            CURRENT_CHAIN(),
            toChain,
            // amount emitted is different than amount in the struct
            // because this is the amount that actually gets sent on this chain
            // it doesn't matter that much anyways since you can always get
            // the exchangeRate and do all the calculations yourself
            (amount - currentFee),
            exchangeRate
        );
    }

    /// @dev fulfills a bridge transaction from another chain
    /// @param transaction bridge transaction to fulfill
    /// @param signature signature for `transaction` signed by RELAYER_ROLE
    function fulfill(FulfillTx calldata transaction, bytes calldata signature)
        external
        whenNotPaused
    {
        require(isSupportedChain(transaction.fromChain), 'Not supported fromChain');
        require(
          !fulfilled[transaction.fromChain][transaction.fromUser][transaction.nonce],
          'Signature already fulfilled'
        );

        bytes32 hashedData = _hashTransaction(transaction);
        require(hasRole(RELAYER_ROLE, _verify(hashedData, signature)), 'Wrong signature');

        fulfilled[transaction.fromChain][transaction.fromUser][transaction.nonce] = true;

        uint256 exchangeRate = exchangeRateFrom[bytes32(bytes(transaction.fromChain))];
        uint256 amount = transaction.amount * exchangeRate;
        uint256 currentFee = (amount * feeFulfill) / FEE_DENOMINATOR;

        _dispenseTokens(transaction.toUser, amount - currentFee);
        if (currentFee != 0) _dispenseTokens(feeWallet, currentFee);

        emit FulfilledTokens(
            transaction.fromUser,
            transaction.toUser,
            transaction.fromChain,
            CURRENT_CHAIN(),
            // amount emitted is different than amount in the struct
            // because this is the amount that actually gets sent on this chain
            // it doesn't matter that much anyways since you can always get
            // the exchangeRate and do all the calculations yourself
            amount - currentFee,
            exchangeRate
        );
    }

    /// @dev add chains to the whitelist
    /// @param chains chains to add
    /// @param exchangeRatesFromPow exchange rates for `chains` as a power of 10.
    ///     exchange rate is a multiplier that fixes the difference
    ///     between decimals on different chains
    function addChains(string[] calldata chains, uint256[] calldata exchangeRatesFromPow)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(chains.length == exchangeRatesFromPow.length, 'bad input');

        for (uint256 i; i < chains.length; ) {
            require(
                availableChainsToSend.add(bytes32(bytes(chains[i]))),
                'Chain is already in the list'
            );

            bytes32 chain = bytes32(bytes(chains[i]));
            // implicitly reverts on overflow
            uint256 exchangeRate = 10 ** exchangeRatesFromPow[i];

            if (exchangeRateFrom[chain] != 0) {
              require(exchangeRateFrom[chain] == exchangeRate, 'cannot modify the exchange rate');
            } else {
              exchangeRateFrom[chain] = exchangeRate;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev remove chains from the whitelist
    /// @param chains chains to remove
    function removeChains(string[] calldata chains)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i; i < chains.length; ) {
            require(
                availableChainsToSend.remove(bytes32(bytes(chains[i]))),
                'Chain is not in the list yet'
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @dev set fees for send and fulfill
    /// @param feeSend_ fee for send as numerator over FEE_DENOMINATOR
    /// @param feeFulfill_ fee for fulfill as numerator over FEE_DENOMINATOR
    function setFee(uint256 feeSend_, uint256 feeFulfill_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            feeSend != feeSend_ || feeFulfill != feeFulfill_,
            'Fee numerator repeats'
        );
        require(feeSend_ < FEE_DENOMINATOR, 'Fee is too high');
        require(feeFulfill_ < FEE_DENOMINATOR, 'Fee is too high');
        feeSend = feeSend_;
        feeFulfill = feeFulfill_;
    }

    /// @dev sets the wallet where fees are sent
    /// @param feeWallet_ fee wallet
    function setFeeWallet(address feeWallet_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feeWallet != feeWallet_, 'Fee wallet repeats');
        require(feeWallet_ != address(0), 'Fee wallet is zero address');
        feeWallet = feeWallet_;
    }

    /// @dev sets the maximum amount of tokens that can be sent in one transaction
    /// @param limitPerSend_ limit value
    function setLimitPerSend(uint256 limitPerSend_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(limitPerSend != limitPerSend_, 'Limit per send repeats');
        limitPerSend = limitPerSend_;
    }

    /// @dev withdraw tokens from bridge
    /// @param token token to withdraw
    /// @param to the address the tokens will be sent
    /// @param amount amount to withdraw
    function withdraw(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SafeERC20.safeTransfer(token, to, amount);
    }

    /// @dev pausing the contract
    function pause() external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @dev unpausing the contract
    function unpause() external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @dev returns a list of bridge transactions sent by `user`
    ///   from the current chain
    /// @param user sender address
    /// @return list of transactions
    function getUserTransactions(address user)
        external
        view
        returns (Transaction[] memory)
    {
        return transactions[user];
    }

    /// @dev returns the amount of bridge transactions sent by `user`
    ///   from the current chain
    /// @param user user
    /// @return amount of transactions
    function getUserTransactionsAmount(address user)
        external
        view
        returns (uint256)
    {
        return transactions[user].length;
    }

    /// @dev getting a list of supported chains
    /// @return list of supported chains
    function supportedChainList() external view returns (bytes32[] memory) {
        return availableChainsToSend.values();
    }

    /// @dev getting if chain is supported
    /// @return is chain supported
    function isSupportedChain(string calldata chain) public view returns (bool) {
        return availableChainsToSend.contains(bytes32(bytes(chain)));
    }

    /// @dev Returns the current chain name as a string.
    /// @return name of the current chain
    function CURRENT_CHAIN() public view returns (string memory) {
        return _toString(CURRENT_CHAIN_B32);
    }

    /// @dev receive `amount` of tokens from address `user`
    /// @param from address to take tokens from
    /// @param amount amount of tokens to take
    function _receiveTokens(address from, uint256 amount) private {
        SafeERC20.safeTransferFrom(TOKEN, from, address(this), amount);
    }

    /// @dev dispense `amount` of tokens to address `to`
    /// @param to address to dispense tokens to
    /// @param amount amount of tokens to dispense
    function _dispenseTokens(address to, uint256 amount) private {
        SafeERC20.safeTransfer(TOKEN, to, amount);
    }

    /// @dev hashes `Transaction` structure with EIP-712 standard
    /// @param transaction `Transaction` structure
    /// @return hash hashed `Transaction` structure
    function _hashTransaction(FulfillTx memory transaction)
        private
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        FULFILL_TX_TYPEHASH,
                        transaction.amount,
                        keccak256(abi.encodePacked(transaction.fromUser)),
                        transaction.toUser,
                        keccak256(abi.encodePacked(transaction.fromChain)),
                        transaction.nonce
                    )
                )
            );
    }

    /// @dev verify whether `signature` of `data` is valid and return the signer address
    /// @param data keccak256 hash of the signed data
    /// @param signature signature of `data`
    /// @return the signer address
    function _verify(bytes32 data, bytes calldata signature)
        private
        pure
        returns (address)
    {
        return ECDSA.recover(data, signature);
    }

    /// @dev converts a null-terminated 32-byte string to a variable length string
    /// @param source null-terminated 32-byte string
    /// @return result a variable length null-terminated string
    function _toString(bytes32 source) private pure returns (string memory result) {
        uint8 length = 0;
        while (source[length] != 0 && length < 32) {
            length++;
        }
        assembly {
            result := mload(0x40)
            // new "memory end" including padding (the string isn't larger than 32 bytes)
            mstore(0x40, add(result, 0x40))
            // store length in memory
            mstore(result, length)
            // write actual data
            mstore(add(result, 0x20), source)
        }
    }
}

