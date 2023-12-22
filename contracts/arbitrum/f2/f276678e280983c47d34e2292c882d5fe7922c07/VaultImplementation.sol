// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./NameVersion.sol";
import "./SafeMath.sol";
import "./MegaSwapper.sol";
import "./ECDSA.sol";
import "./ISwapper.sol";
import "./IUpdateState.sol";
import "./UpdateStateStorage.sol";
import "./VaultStorage.sol";
import "./SafeERC20.sol";

contract VaultImplementation is VaultStorage, NameVersion {
    using SafeERC20 for IERC20;

    event AddSigner(address signer);

    event RemoveSigner(address signer);

    event AddAsset(address asset);

    event RemoveAsset(address asset);

    event Deposit(
        address indexed token,
        address indexed account,
        uint256 amount
    );

    event Withdraw(
        address indexed token,
        address indexed account,
        uint256 amount,
        uint256 expiry,
        uint256 nonce,
        bytes signatures
    );

    using SafeMath for uint256;

    using SafeMath for int256;

    string public constant name = "Vault";

    uint256 public immutable chainId;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256(
            "Withdraw(address token,address account,uint256 amount,uint256 expiry,uint256 nonce)"
        );

    ISwapper public immutable swapper;

    address public immutable update;

    address public immutable marketVault;

    constructor(
        address _swapper,
        address _update,
        address _marketVault
    ) NameVersion("VaultImplementation", "1.0.0") {
        uint256 _chainId;
        assembly {
            _chainId := chainid()
        }
        chainId = _chainId;
        swapper = ISwapper(_swapper);
        update = _update;
        marketVault = _marketVault;
    }

    function initializeDomain() external {
        domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                chainId,
                address(this)
            )
        );
    }

    // ========================================================
    // balance update
    // ========================================================
    function setOperator(
        address operator_,
        bool isActive
    ) external _onlyAdmin_ {
        isOperator[operator_] = isActive;
    }

    // ONLY AVAILABLE ON ARBITRUM
    function transferOut(
        address account,
        address asset,
        uint256 amount
    ) external _notPaused_ _reentryLock_ {
        require(msg.sender == update, "vault: only update contract");
        if (asset == address(0)) {
            _transferOutETH(account, amount);
        } else {
            IERC20(asset).safeTransfer(account, amount);
        }
    }

    function settleMarketVault(
        address asset,
        uint256 amount
    ) external _notPaused_ {
        require(msg.sender == marketVault, "vault: only market maker vault");
        if (asset == address(0)) {
            uint256 balance = address(this).balance;
            if (amount > balance) {
                _transferOutETH(marketVault, balance);
                uint256 debtAmount = amount - balance;
                debtToMarketVault[asset] += debtAmount;
            } else {
                _transferOutETH(marketVault, amount);
            }
        } else {
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (amount > balance) {
                IERC20(asset).safeTransfer(marketVault, balance);
                uint256 debtAmount = amount - balance;
                debtToMarketVault[asset] += debtAmount;
            } else {
                IERC20(asset).safeTransfer(marketVault, amount);
            }
        }
    }

    function repayMarketVault(
        address asset
    ) external _notPaused_ _reentryLock_ {
        uint256 debtAmount = debtToMarketVault[asset];
        require(debtAmount > 0, "vault: no debt");
        if (asset == address(0)) {
            require(
                debtAmount <= address(this).balance,
                "vault: transfer exceed balance"
            );
            debtToMarketVault[asset] = 0;
            _transferOutETH(marketVault, debtAmount);
        } else {
            require(
                debtAmount <= IERC20(asset).balanceOf(address(this)),
                "vault: transfer exceed balance"
            );
            debtToMarketVault[asset] = 0;
            IERC20(asset).safeTransfer(marketVault, debtAmount);
        }
    }

    function pause() external _onlyAdmin_ _notPaused_ {
        _paused = true;
    }

    function unpause() external _onlyAdmin_ {
        _paused = false;
    }

    // ========================================================
    // udpate signers
    // ========================================================
    function addSigner(address newSigner) external _onlyAdmin_ {
        require(!isValidSigner[newSigner], "vault: duplicate signer");
        validSigners.push(newSigner);
        isValidSigner[newSigner] = true;
        validatorIndex[newSigner] = validSigners.length;
        emit AddSigner(newSigner);
    }

    function removeSigner(address removedSigner) external _onlyAdmin_ {
        require(isValidSigner[removedSigner], "vault: not a valid signer");
        uint256 length = validSigners.length;
        for (uint256 i = 0; i < length; ++i) {
            if (validSigners[i] == removedSigner) {
                validSigners[i] = validSigners[length - 1];
                break;
            }
        }
        validSigners.pop();
        validatorIndex[removedSigner] = 0;
        isValidSigner[removedSigner] = false;

        uint256 len = validSigners.length;
        for (uint i = 0; i < len; ++i) {
            validatorIndex[validSigners[i]] = i + 1;
        }
        emit RemoveSigner(removedSigner);
    }

    function setSignatureThreshold(
        uint256 newSignatureThreshold
    ) external _onlyAdmin_ {
        signatureThreshold = newSignatureThreshold;
    }

    // ========================================================
    // Asset Management
    // ========================================================
    function addAsset(address asset) external {
        require(isOperator[msg.sender], "vault: only operator");
        require(!supportedAsset[asset], "vault: asset already added");
        indexedAssets.push(asset);
        supportedAsset[asset] = true;
        emit AddAsset(asset);
    }

    function removeAsset(address asset) external {
        require(isOperator[msg.sender], "vault: only operator");
        require(supportedAsset[asset], "vault: asset not found");
        uint256 length = indexedAssets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (indexedAssets[i] == asset) {
                indexedAssets[i] = indexedAssets[length - 1];
                break;
            }
        }
        indexedAssets.pop();
        supportedAsset[asset] = false;
        emit RemoveAsset(asset);
    }

    // ========================================================
    // deposit&withdraw
    // ========================================================
    function swapAndDeposit(
        address inToken,
        address outToken,
        uint256 inAmount,
        address caller,
        bytes calldata data
    ) external payable _reentryLock_ _notPaused_ {
        require(supportedAsset[outToken], "vault: unsupported asset");
        address account = msg.sender;
        uint256 outAmount;
        if (inToken == address(0)) {
            require(
                msg.value > 0 && msg.value == inAmount,
                "vault: wrong ETH amount"
            );
            outAmount = swapper.swap{value: msg.value}(
                inToken,
                outToken,
                inAmount,
                caller,
                data
            );
        } else {
            require(inAmount > 0, "vault: amount should be greater than 0");
            IERC20(inToken).safeTransferFrom(
                account,
                address(swapper),
                inAmount
            );
            outAmount = swapper.swap(inToken, outToken, inAmount, caller, data);
        }

        if (outToken == address(0)) {
            emit Deposit(address(0), account, outAmount);
        } else {
            emit Deposit(outToken, account, outAmount);
        }
    }

    function deposit(
        address token,
        uint256 amount
    ) public payable _reentryLock_ _notPaused_ {
        address account = msg.sender;
        require(supportedAsset[token], "vault: unsupported asset");
        if (token == address(0)) {
            require(
                msg.value > 0 && msg.value == amount,
                "vault: wrong ETH amount"
            );
            emit Deposit(address(0), account, amount);
        } else {
            require(amount > 0, "vault: amount should be greater than 0");
            IERC20(token).safeTransferFrom(account, address(this), amount);
            emit Deposit(token, account, amount);
        }
    }

    function withdraw(
        address token,
        uint256 amount,
        uint256 expiry,
        uint256 nonce,
        bytes calldata signatures
    ) external _reentryLock_ _notPaused_ {
        address account = msg.sender;
        require(expiry >= block.timestamp, "vault: withdraw expired");
        _checkSignature(token, amount, expiry, nonce, signatures);
        // reset freeze start
        if (update != address(0)) IUpdateState(update).resetFreezeStart();

        if (token == address(0)) {
            _transferOutETH(account, amount);
        } else {
            IERC20(token).safeTransfer(account, amount);
        }
        emit Withdraw(token, account, amount, expiry, nonce, signatures);
    }

    function swapAndWithdraw(
        address inToken,
        uint256 inAmount,
        uint256 expiry,
        uint256 nonce,
        bytes calldata signatures,
        address outToken,
        address caller,
        bytes calldata data
    ) external _reentryLock_ _notPaused_ {
        address account = msg.sender;
        require(expiry >= block.timestamp, "vault: withdraw expired");
        _checkSignature(inToken, inAmount, expiry, nonce, signatures);
        // reset freeze start
        if (update != address(0)) IUpdateState(update).resetFreezeStart();

        uint256 outAmount;
        if (inToken == address(0)) {
            outAmount = swapper.swap{value: inAmount}(
                inToken,
                outToken,
                inAmount,
                caller,
                data
            );
        } else {
            IERC20(inToken).safeTransfer(address(swapper), inAmount);
            outAmount = swapper.swap(inToken, outToken, inAmount, caller, data);
        }
        if (outToken == address(0)) {
            _transferOutETH(account, outAmount);
        } else {
            IERC20(outToken).safeTransfer(account, outAmount);
        }
        emit Withdraw(inToken, account, inAmount, expiry, nonce, signatures);
    }

    function _checkSignature(
        address token,
        uint256 amount,
        uint256 expiry,
        uint256 nonce,
        bytes calldata signatures
    ) internal {
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAW_TYPEHASH,
                token,
                msg.sender,
                amount,
                expiry,
                nonce
            )
        );
        require(!usedHash[structHash], "vault: withdraw replay");
        usedHash[structHash] = true;

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        require(signatures.length % 65 == 0, "vault: invalid signature length");
        uint256 signatureCount = signatures.length / 65;
        require(
            signatureCount >= signatureThreshold,
            "vault: wrong number of signatures"
        );

        address recovered;
        uint256 validCount;
        bool[] memory signerIndexVisited = new bool[](validSigners.length);

        for (uint i = 0; i < signatureCount; ++i) {
            recovered = ECDSA.recover(digest, signatures[i * 65:(i + 1) * 65]);
            if (
                isValidSigner[recovered] &&
                !signerIndexVisited[_validatorRealIndex(recovered)]
            ) {
                validCount++;
                signerIndexVisited[_validatorRealIndex(recovered)] = true;
            }
        }
        require(
            validCount >= signatureThreshold,
            "vault:number of signers not reach limit"
        );
    }

    function _transferOutETH(address receiver, uint256 amountOut) internal {
        (bool success, ) = payable(receiver).call{value: amountOut}("");
        require(success, "vault: send ETH fail");
    }

    function _validatorRealIndex(
        address validator
    ) internal view returns (uint256) {
        uint256 idx = validatorIndex[validator];
        require(idx > 0, "validator is not valid");
        return idx - 1;
    }
}

