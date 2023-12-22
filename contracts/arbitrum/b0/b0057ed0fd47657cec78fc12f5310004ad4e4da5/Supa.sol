// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Proxy} from "./Proxy.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC721} from "./ERC721.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";
import {Address} from "./Address.sol";

import {     ISupaCore,     ERC20Share,     ERC20Pool,     ERC20Info,     ERC721Info,     ContractData,     ContractKind } from "./ISupa.sol";
import {SupaState} from "./SupaState.sol";
import {WalletProxy} from "./WalletProxy.sol";
import {IVersionManager} from "./IVersionManager.sol";
import {IERC1363SpenderExtended} from "./IERC1363-extended.sol";
import {WalletLib} from "./WalletLib.sol";
import {ERC20PoolLib} from "./ERC20PoolLib.sol";
import {Call} from "./Call.sol";
import {FsUtils} from "./FsUtils.sol";
import {FsMath} from "./FsMath.sol";

import {IERC20ValueOracle} from "./IERC20ValueOracle.sol";
import {INFTValueOracle} from "./INFTValueOracle.sol";

import {Errors} from "./Errors.sol";

// ERC20 standard token
// ERC721 single non-fungible token support
// ERC677 transferAndCall (transferAndCall2 extension)
// ERC165 interface support (solidity ISupa.interfaceId)
// ERC777 token send
// ERC1155 multi-token support
// ERC1363 payable token (approveAndCall/transferAndCall)
// ERC1820 interface registry support
// EIP2612 permit support (uniswap permit2)
/*
 * NFTs are stored in an array of nfts owned by some wallet. To prevent looping over arrays we need to
 * know the following information for each NFT in the system (erc721, tokenId, wallet, array index).
 * Given the expensive nature of storage on the EVM we want to store all information as small as possible.
 * The pair (erc721, tokenId) is describes a particular NFT but would take two storage slots (as a token id)
 * is 256 bits. The erc721 address is 160 bits however we only allow pre-approved erc721 contracts, so in
 * practice 16 bits would be enough to store an index into the allowed erc721 contracts. We can hash (erc721 + tokenId)
 * to get a unique number but that requires storing both tokenId, erc721 and array index. Instead we hash into
 * 224 (256 - 32) bits which is still sufficiently large to avoid collisions. This leaves 32 bits for additional
 * information. The 16 LSB are used to store the index in the wallet array. The 16 RSB are used to store
 * the 16 RSB of the tokenId. This allows us to store the tokenId + array index in a single storage slot as a map
 * from NFTId to NFTData. Note that the index in the wallet array might change and thus cannot be part of
 * NFTId and thus has to be stored as part of NFTData, requiring the splitting of tokenId.
 */

/// @title Supa
contract Supa is SupaState, ISupaCore, IERC721Receiver, Proxy {
    using WalletLib for WalletLib.Wallet;
    using ERC20PoolLib for ERC20Pool;
    using SafeERC20 for IERC20;
    using Address for address;

    // We will initialize the system so that 0 is the base currency
    // in which the system calculates value.
    uint16 constant private K_NUMERAIRE_IDX = 0;

    uint256 constant private POOL_ASSETS_CUTOFF = 100; // Wei amounts to prevent division by zero

    address immutable private supaConfigAddress;

    modifier onlyRegisteredNFT(address nftContract, uint256 tokenId) {
        // how can we be sure that Oracle would have a price for any possible tokenId?
        // maybe we should check first if Oracle can return a value for this specific NFT?
        if (infoIdx[nftContract].kind == ContractKind.Invalid) {
            revert Errors.NotRegistered(nftContract);
        }
        _;
    }

    modifier onlyNFTOwner(address nftContract, uint256 tokenId) {
        address _owner = ERC721(nftContract).ownerOf(tokenId);
        bool isOwner = _owner == msg.sender || _owner == wallets[msg.sender].owner;
        if (!isOwner) {
            revert Errors.NotNFTOwner();
        }
        _;
    }

    constructor(address supaConfig, address versionManagerAddress) {
        versionManager = IVersionManager(FsUtils.nonNull(versionManagerAddress));
        supaConfigAddress = FsUtils.nonNull(supaConfig);
    }

    /// @inheritdoc ISupaCore
    function depositERC20ForWallet(address erc20, address to, uint256 amount)
        external
        override
        walletExists(to)
        whenNotPaused
    {
        if (amount == 0) return;
        (, uint16 erc20Idx) = getERC20Info(IERC20(erc20));
        int256 signedAmount = FsMath.safeCastToSigned(amount);
        _creditAccountERC20ChangeBy(to, erc20Idx, signedAmount);
        emit ISupaCore.ERC20BalanceChanged(erc20, erc20Idx, to, signedAmount);
        IERC20(erc20).safeTransferFrom(msg.sender, address(this), amount);
        _tokenStorageCheck(to);
    }

    /// @inheritdoc ISupaCore
    function depositERC20(IERC20 erc20, uint256 amount) external override onlyWallet whenNotPaused {
        if (amount == 0) return;
        (, uint16 erc20Idx) = getERC20Info(erc20);
        int256 signedAmount = FsMath.safeCastToSigned(amount);
        _creditAccountERC20ChangeBy(msg.sender, erc20Idx, signedAmount);
        emit ISupaCore.ERC20BalanceChanged(address(erc20), erc20Idx, msg.sender, signedAmount);
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        _tokenStorageCheck(msg.sender);
    }

    /// @inheritdoc ISupaCore
    function withdrawERC20(IERC20 erc20, uint256 amount) external override onlyWallet whenNotPaused {
        (, uint16 erc20Idx) = getERC20Info(erc20);
        int256 signedAmount = FsMath.safeCastToSigned(amount);
        _creditAccountERC20ChangeBy(msg.sender, erc20Idx, -signedAmount);
        emit ISupaCore.ERC20BalanceChanged(address(erc20), erc20Idx, msg.sender, -signedAmount);
        erc20.safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc ISupaCore
    function depositFull(IERC20[] calldata erc20s) external override onlyWallet whenNotPaused {
        for (uint256 i = 0; i < erc20s.length; i++) {
            (ERC20Info storage erc20Info, uint16 erc20Idx) = getERC20Info(erc20s[i]);
            IERC20 erc20 = IERC20(erc20Info.erc20Contract);
            uint256 amount = erc20.balanceOf(msg.sender);
            int256 signedAmount = FsMath.safeCastToSigned(amount);
            _creditAccountERC20ChangeBy(msg.sender, erc20Idx, signedAmount);
            emit ISupaCore.ERC20BalanceChanged(address(erc20), erc20Idx, msg.sender, signedAmount);
            erc20.safeTransferFrom(msg.sender, address(this), amount);
        }
        _tokenStorageCheck(msg.sender);
    }

    /// @inheritdoc ISupaCore
    function withdrawFull(IERC20[] calldata erc20s) external onlyWallet whenNotPaused {
        for (uint256 i = 0; i < erc20s.length; i++) {
            (ERC20Info storage erc20Info, uint16 erc20Idx) = getERC20Info(erc20s[i]);
            IERC20 erc20 = IERC20(erc20Info.erc20Contract);
            int256 amount = _creditAccountERC20Clear(msg.sender, erc20Idx);
            if (amount < 0) {
                revert Errors.CannotWithdrawDebt();
            }
            emit ISupaCore.ERC20BalanceChanged(address(erc20), erc20Idx, msg.sender, amount);
            erc20.safeTransfer(msg.sender, uint256(amount));
        }
    }

    /// @inheritdoc ISupaCore
    function depositERC721(address erc721Contract, uint256 tokenId)
        external
        override
        onlyWallet
        whenNotPaused
        onlyRegisteredNFT(erc721Contract, tokenId)
        onlyNFTOwner(erc721Contract, tokenId)
    {
        address _owner = ERC721(erc721Contract).ownerOf(tokenId);
        emit ISupaCore.ERC721Deposited(erc721Contract, msg.sender, tokenId);
        ERC721(erc721Contract).safeTransferFrom(_owner, address(this), tokenId, abi.encode(msg.sender));
    }

    /// @inheritdoc ISupaCore
    function depositERC721ForWallet(address erc721Contract, address to, uint256 tokenId)
        external
        override
        walletExists(to)
        whenNotPaused
        onlyRegisteredNFT(erc721Contract, tokenId)
        onlyNFTOwner(erc721Contract, tokenId)
    {
        address _owner = ERC721(erc721Contract).ownerOf(tokenId);
        emit ISupaCore.ERC721Deposited(erc721Contract, to, tokenId);
        ERC721(erc721Contract).safeTransferFrom(_owner, address(this), tokenId, abi.encode(to));
    }

    /// @inheritdoc ISupaCore
    function withdrawERC721(address erc721, uint256 tokenId) external override onlyWallet whenNotPaused {
        WalletLib.NFTId nftId = _getNFTId(erc721, tokenId);

        wallets[msg.sender].extractNFT(nftId, tokenDataByNFTId);
        delete tokenDataByNFTId[nftId];
        emit ISupaCore.ERC721Withdrawn(erc721, msg.sender, tokenId);

        ERC721(erc721).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /// @inheritdoc ISupaCore
    function transferERC20(IERC20 erc20, address to, uint256 amount)
        external
        override
        onlyWallet
        whenNotPaused
        walletExists(to)
    {
        if (amount == 0) return;
        _transferERC20(erc20, msg.sender, to, FsMath.safeCastToSigned(amount));
    }

    /// @inheritdoc ISupaCore
    function transferERC721(address erc721, uint256 tokenId, address to)
        external
        override
        onlyWallet
        whenNotPaused
        walletExists(to)
    {
        WalletLib.NFTId nftId = _getNFTId(erc721, tokenId);
        _transferNFT(nftId, msg.sender, to);
    }

    /// @inheritdoc ISupaCore
    function transferFromERC20(address erc20, address from, address to, uint256 amount)
        external
        override
        whenNotPaused
        walletExists(from)
        walletExists(to)
        returns (bool)
    {
        address spender = msg.sender;
        _spendAllowance(erc20, from, spender, amount);
        _transferERC20(IERC20(erc20), from, to, FsMath.safeCastToSigned(amount));
        return true;
    }

    /// @inheritdoc ISupaCore
    function transferFromERC721(address collection, address from, address to, uint256 tokenId)
        external
        override
        onlyWallet
        whenNotPaused
        walletExists(to)
    {
        WalletLib.NFTId nftId = _getNFTId(collection, tokenId);
        if (!_isApprovedOrOwner(msg.sender, nftId)) {
            revert Errors.NotApprovedOrOwner();
        }
        _transferNFT(nftId, from, to);
    }

    /// @inheritdoc ISupaCore
    function liquidate(address wallet) external override onlyWallet whenNotPaused walletExists(wallet) {
        (int256 totalValue, int256 collateral, int256 debt) = getRiskAdjustedPositionValues(wallet);
        if (collateral >= debt) {
            revert Errors.NotLiquidatable();
        }
        uint16[] memory walletERC20s = wallets[wallet].getERC20s();
        for (uint256 i = 0; i < walletERC20s.length; i++) {
            uint16 erc20Idx = walletERC20s[i];
            _transferAllERC20(erc20Idx, wallet, msg.sender);
        }
        while (wallets[wallet].nfts.length > 0) {
            _transferNFT(wallets[wallet].nfts[wallets[wallet].nfts.length - 1], wallet, msg.sender);
        }
        if (totalValue > 0) {
            // totalValue of the liquidated wallet is split between liquidatable and liquidator:
            // totalValue * (1 - liqFraction) - reward of the liquidator, and
            // totalValue * liqFraction - change, liquidator is sending back to liquidatable
            int256 percentUnderwater = (collateral * 1 ether) / debt;
            int256 leftover = ((totalValue * config.liqFraction * percentUnderwater) / 1 ether) / 1 ether;
            _transferERC20(IERC20(erc20Infos[K_NUMERAIRE_IDX].erc20Contract), msg.sender, wallet, leftover);
        }
        emit ISupaCore.WalletLiquidated(wallet, msg.sender, collateral, debt);
    }

    /// @inheritdoc ISupaCore
    function addOperator(address operator) external override onlyWallet {
        operatorApprovals[msg.sender][operator] = true;
        emit OperatorAdded(msg.sender, operator);
    }

    /// @inheritdoc ISupaCore
    function removeOperator(address operator) external override onlyWallet {
        operatorApprovals[msg.sender][operator] = false;
        emit OperatorRemoved(msg.sender, operator);
    }

    /// @notice Unused function. Will be used in future versions
    /// @dev (address wallet, address owner, address implementation)
    function migrateWallet(address, address, address) external override pure {
        revert Errors.NotImplemented();
    }

    /// @inheritdoc ISupaCore
    function executeBatch(Call[] memory calls) external override onlyWallet whenNotPaused {
        WalletProxy(payable(msg.sender)).executeBatch(calls);
        if (!isSolvent(msg.sender)) {
            revert Errors.Insolvent();
        }
    }

    /// @notice ERC721 transfer callback
    /// @dev it's a callback, required to be implemented by IERC721Receiver interface for the
    /// contract to be able to receive ERC721 NFTs.
    /// We are using it to track what creditAccount owns what NFT.
    /// `return this.onERC721Received.selector;` is mandatory part for the NFT transfer to work -
    /// not a part of our business logic
    /// @param - operator The address which called `safeTransferFrom` function
    /// @param from The address which previously owned the token
    /// @param tokenId The NFT identifier which is being transferred
    /// @param data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    function onERC721Received(address, /* operator */ address from, uint256 tokenId, bytes calldata data)
        external
        override
        whenNotPaused
        returns (bytes4)
    {
        WalletLib.NFTId nftId = _getNFTId(msg.sender, tokenId);
        if (data.length != 0) {
            from = abi.decode(data, (address));
        }
        if (wallets[from].owner == address(0)) {
            revert Errors.WalletNonExistent();
        }
        tokenDataByNFTId[nftId].tokenId = uint240(tokenId);
        wallets[from].insertNFT(nftId, tokenDataByNFTId);
        _tokenStorageCheck(from);
        emit ISupaCore.ERC721Received(from, msg.sender, tokenId);
        return this.onERC721Received.selector;
    }

    /// @inheritdoc ISupaCore
    function approveAndCall(Approval[] calldata approvals, address spender, bytes calldata data)
        external
        override
        onlyWallet
        whenNotPaused
    {
        uint256[] memory prev = new uint256[](approvals.length);
        for (uint256 i = 0; i < approvals.length; i++) {
            prev[i] = _approve(msg.sender, spender, approvals[i].ercContract, approvals[i].amountOrTokenId, spender);
        }
        if (!_checkOnApprovalReceived(msg.sender, 0, spender, data)) {
            revert Errors.WrongDataReturned();
        }
        for (uint256 i = 0; i < approvals.length; i++) {
            _approve(msg.sender, spender, approvals[i].ercContract, prev[i], address(0)); // reset allowance
        }
    }

    /// @inheritdoc ISupaCore
    function getImplementation(address wallet) external view override returns (address) {
        // not using msg.sender since this is an external view function
        return walletLogic[wallet];
    }

    /// @inheritdoc ISupaCore
    function getWalletOwner(address wallet) external view override returns (address) {
        return wallets[wallet].owner;
    }

    /// @notice Get the token data for a given NFT ID
    /// @param nftId The NFT ID to get the token data for
    /// @return erc721 The address of the ERC721 contract
    /// @return tokenId The token ID
    function getERC721DataFromNFTId(WalletLib.NFTId nftId) external view returns (address erc721, uint256 tokenId) {
        uint16 erc721Idx;
        (erc721Idx, tokenId) = getNFTData(nftId);
        erc721 = erc721Infos[erc721Idx].erc721Contract;
        return (erc721, tokenId);
    }

    /// @inheritdoc ISupaCore
    function getRiskAdjustedPositionValues(address walletAddress)
        public
        view
        override
        walletExists(walletAddress)
        returns (int256 totalValue, int256 collateral, int256 debt)
    {
        WalletLib.Wallet storage wallet = wallets[walletAddress];
        uint16[] memory erc20Idxs = wallet.getERC20s();
        totalValue = 0;
        collateral = 0;
        debt = 0;
        for (uint256 i = 0; i < erc20Idxs.length; i++) {
            uint16 erc20Idx = erc20Idxs[i];
            ERC20Info storage erc20Info = erc20Infos[erc20Idx];
            int256 balance = getBalance(wallet.erc20Share[erc20Idx], erc20Info);
            (int256 value, int256 riskAdjustedValue) = erc20Info.valueOracle.calcValue(balance);
            totalValue += value;
            if (balance >= 0) {
                collateral += riskAdjustedValue;
            } else {
                debt -= riskAdjustedValue;
            }
        }
        for (uint256 i = 0; i < wallet.nfts.length; i++) {
            WalletLib.NFTId nftId = wallet.nfts[i];
            (uint16 erc721Idx, uint256 tokenId) = getNFTData(nftId);
            ERC721Info storage nftInfo = erc721Infos[erc721Idx];
            (int256 nftValue, int256 nftRiskAdjustedValue) = nftInfo.valueOracle.calcValue(tokenId);
            totalValue += nftValue;
            collateral += nftRiskAdjustedValue;
        }
    }

    /// @inheritdoc ISupaCore
    function getApproved(address collection, uint256 tokenId) public view override returns (address) {
        WalletLib.NFTId nftId = _getNFTId(collection, tokenId);
        return tokenDataByNFTId[nftId].approvedSpender;
    }

    /// @inheritdoc ISupaCore
    function isOperator(address _owner, address spender) public view override returns (bool) {
        return operatorApprovals[_owner][spender];
    }

    /// @inheritdoc ISupaCore
    function allowance(address erc20, address _owner, address spender) public view override returns (uint256) {
        if (_owner == spender) return type(uint256).max;
        return allowances[_owner][erc20][spender];
    }

    /// @inheritdoc ISupaCore
    function computeInterestRate(uint16 erc20Idx) public view override returns (int96) {
        ERC20Info memory erc20Info = erc20Infos[erc20Idx];
        uint256 debt = FsMath.safeCastToUnsigned(-erc20Info.debt.tokens); // question: is debt ever positive?
        uint256 collateral = FsMath.safeCastToUnsigned(erc20Info.collateral.tokens); // question: is collateral ever negative?
        uint256 leverage = FsMath.safeCastToUnsigned(config.fractionalReserveLeverage);
        uint256 poolAssets = debt + collateral;

        uint256 ir = erc20Info.baseRate;
        uint256 utilization; // utilization of the pool
        if (poolAssets <= POOL_ASSETS_CUTOFF) {
            utilization = 0;
        } // if there are no assets, utilization is 0
        else {
            utilization = uint256((debt * 1e18) / ((collateral - debt) / leverage));
        }

        if (utilization <= erc20Info.targetUtilization) {
            ir += (utilization * erc20Info.slope1) / 1e15;
        } else {
            ir += (erc20Info.targetUtilization * erc20Info.slope1) / 1e15;
            ir += ((erc20Info.slope2 * (utilization - erc20Info.targetUtilization)) / 1e15);
        }

        return int96(int256(ir));
    }

    /// @inheritdoc ISupaCore
    function isSolvent(address wallet) public view returns (bool) {
        uint256 gasBefore = gasleft();
        int256 leverage = config.fractionalReserveLeverage;
        for (uint256 i = 0; i < erc20Infos.length; i++) {
            int256 totalDebt = erc20Infos[i].debt.tokens;
            int256 reserve = erc20Infos[i].collateral.tokens + totalDebt;
            FsUtils.Assert(IERC20(erc20Infos[i].erc20Contract).balanceOf(address(this)) >= uint256(reserve));
            if (reserve < -totalDebt / leverage) {
                revert Errors.InsufficientReserves();
            }
        }
        (, int256 collateral, int256 debt) = getRiskAdjustedPositionValues(wallet);
        if (gasBefore - gasleft() > config.maxSolvencyCheckGasCost) {
            revert Errors.SolvencyCheckTooExpensive();
        }
        return collateral >= debt;
    }

    function _approve(
        address _owner,
        address spender,
        address ercContract,
        uint256 amountOrTokenId,
        address erc721Spender
    ) internal returns (uint256 prev) {
        FsUtils.Assert(spender != address(0));
        ContractData memory data = infoIdx[ercContract];
        if (data.kind == ContractKind.ERC20) {
            prev = allowance(ercContract, _owner, spender);
            allowances[_owner][ercContract][spender] = amountOrTokenId;
        } else if (data.kind == ContractKind.ERC721) {
            prev = amountOrTokenId;
            tokenDataByNFTId[_getNFTId(ercContract, amountOrTokenId)].approvedSpender = erc721Spender;
        } else {
            FsUtils.Assert(false);
        }
    }

    /// @dev changes the quantity of `erc20` by `amount` that are allowed to transfer from creditAccount
    /// of wallet `_owner` by wallet `spender`
    function _spendAllowance(address erc20, address _owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(erc20, _owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert Errors.InsufficientAllowance();
            }
            unchecked {
                allowances[_owner][erc20][spender] = currentAllowance - amount;
            }
        }
    }

    /**
     * @dev Internal function to invoke {IERC1363Receiver-onApprovalReceived} on a target address
     *  The call is not executed if the target address is not a contract
     * @param spender address The address which will spend the funds
     * @param amount uint256 The amount of tokens to be spent
     * @param data bytes Optional data to send along with the call
     * @return whether the call correctly returned the expected magic value
     */
    function _checkOnApprovalReceived(
        address spender, // safe
        uint256 amount,
        address target, // router
        bytes memory data
    ) internal returns (bool) {
        if (!spender.isContract()) {
            revert Errors.ReceiverNotContract();
        }

        Call memory call = Call({to: target, callData: data, value: msg.value});

        try IERC1363SpenderExtended(spender).onApprovalReceived(msg.sender, amount, call) returns (bytes4 retval) {
            return retval == IERC1363SpenderExtended.onApprovalReceived.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert Errors.ReceiverNoImplementation();
            } else {
                FsUtils.revertBytes(reason);
            }
        }
    }

    /// @dev transfer ERC20 balances between creditAccounts.
    /// Because all ERC20 tokens on creditAccounts are owned by Supa, no tokens are getting transferred -
    /// all changes are inside Supa contract state
    /// @param erc20 The address of ERC20 token balance to transfer
    /// @param from The address of wallet whose creditAccount balance should be decreased by `amount`
    /// @param to The address of wallet whose creditAccount balance should be increased by `amount`
    /// @param amount The amount of `erc20` by witch the balance of
    /// creditAccount of wallet `from` should be decreased and
    /// creditAccount of wallet `to` should be increased.
    /// Note that amount it can be negative
    function _transferERC20(IERC20 erc20, address from, address to, int256 amount) internal {
        (, uint16 erc20Idx) = getERC20Info(erc20);
        _creditAccountERC20ChangeBy(from, erc20Idx, -amount);
        _creditAccountERC20ChangeBy(to, erc20Idx, amount);
        _tokenStorageCheck(to);
        emit ISupaCore.ERC20Transfer(address(erc20), erc20Idx, from, to, amount);
    }

    /// @dev transfer ERC721 NFT ownership between creditAccounts.
    /// Because all ERC721 NFTs on creditAccounts are owned by Supa, no NFT is getting transferred - all
    /// changes are inside Supa contract state
    function _transferNFT(WalletLib.NFTId nftId, address from, address to) internal {
        wallets[from].extractNFT(nftId, tokenDataByNFTId);
        wallets[to].insertNFT(nftId, tokenDataByNFTId);
        _tokenStorageCheck(to);
        emit ERC721Transferred(WalletLib.NFTId.unwrap(nftId), from, to);
    }

    /// @dev transfer all `erc20Idx` from `from` to `to`
    function _transferAllERC20(uint16 erc20Idx, address from, address to) internal {
        int256 amount = _creditAccountERC20Clear(from, erc20Idx);
        _creditAccountERC20ChangeBy(to, erc20Idx, amount);
        address erc20 = erc20Infos[erc20Idx].erc20Contract;
        emit ISupaCore.ERC20Transfer(erc20, erc20Idx, from, to, amount);
    }

    function _creditAccountERC20ChangeBy(address walletAddress, uint16 erc20Idx, int256 amount) internal {
        _updateInterest(erc20Idx);
        WalletLib.Wallet storage wallet = wallets[walletAddress];
        ERC20Share shares = wallet.erc20Share[erc20Idx];
        ERC20Info storage erc20Info = erc20Infos[erc20Idx];
        int256 currentAmount = _extractPosition(shares, erc20Info);
        int256 newAmount = currentAmount + amount;
        wallet.erc20Share[erc20Idx] = _insertPosition(newAmount, wallet, erc20Idx);
    }

    function _creditAccountERC20Clear(address walletAddress, uint16 erc20Idx) internal returns (int256) {
        _updateInterest(erc20Idx);
        WalletLib.Wallet storage wallet = wallets[walletAddress];
        ERC20Share shares = wallet.erc20Share[erc20Idx];
        int256 erc20Amount = _extractPosition(shares, erc20Infos[erc20Idx]);
        wallet.erc20Share[erc20Idx] = ERC20Share.wrap(0);
        wallet.removeERC20IdxFromCreditAccount(erc20Idx);
        return erc20Amount;
    }

    function _extractPosition(ERC20Share sharesWrapped, ERC20Info storage erc20Info)
        internal
        returns (int256 position)
    {
        int256 shares = ERC20Share.unwrap(sharesWrapped);
        ERC20Pool storage pool = shares > 0 ? erc20Info.collateral : erc20Info.debt;
        position = pool.extractPosition(sharesWrapped);
        return position;
    }

    function _insertPosition(int256 amount, WalletLib.Wallet storage wallet, uint16 erc20Idx)
        internal
        returns (ERC20Share)
    {
        if (amount == 0) {
            wallet.removeERC20IdxFromCreditAccount(erc20Idx);
        } else {
            wallet.addERC20IdxToCreditAccount(erc20Idx);
        }
        ERC20Info storage erc20Info = erc20Infos[erc20Idx];
        ERC20Pool storage pool = amount > 0 ? erc20Info.collateral : erc20Info.debt;
        return pool.insertPosition(amount);
    }

    function _updateInterest(uint16 erc20Idx) internal {
        ERC20Info storage erc20Info = erc20Infos[erc20Idx]; // retrieve ERC20Info and store in memory
        if (erc20Info.timestamp == block.timestamp) return; // already updated this block
        int256 delta = FsMath.safeCastToSigned(block.timestamp - erc20Info.timestamp); // time passed since last update
        erc20Info.timestamp = block.timestamp; // update timestamp to current timestamp
        int256 debt = -erc20Info.debt.tokens; // get the debt
        int256 interestRate = computeInterestRate(erc20Idx);
        int256 interest =
            (debt * (FsMath.exp(interestRate * delta) - FsMath.FIXED_POINT_SCALE)) / FsMath.FIXED_POINT_SCALE; // Get the interest
        int256 treasuryInterest = (interest * FsMath.safeCastToSigned(config.treasuryInterestFraction)) / 1 ether; // Get the treasury interest
        erc20Info.debt.tokens -= interest; // subtract interest from debt (increase)
        erc20Info.collateral.tokens += interest - treasuryInterest; // add interest to collateral (increase)

        _creditAccountERC20ChangeBy(config.treasuryWallet, erc20Idx, treasuryInterest); // add treasury interest to treasury
    }

    function _tokenStorageCheck(address walletAddress) internal view {
        WalletLib.Wallet storage wallet = wallets[walletAddress];
        uint256 tokenCounter;
        uint256 nftCounter = wallet.nfts.length;
        if (wallet.tokenCounter < 0) {
            tokenCounter = 0;
        } else {
            tokenCounter = FsMath.safeCastToUnsigned(wallet.tokenCounter);
        }
        uint256 tokenStorage =
            (tokenCounter * tokenStorageConfig.erc20Multiplier) + (nftCounter * tokenStorageConfig.erc721Multiplier);
        if (tokenStorage > tokenStorageConfig.maxTokenStorage) {
            revert Errors.TokenStorageExceeded();
        }
    }

    function _getNFTId(address erc721, uint256 tokenId) internal view returns (WalletLib.NFTId) {
        if (infoIdx[erc721].kind != ContractKind.ERC721) {
            revert Errors.NotNFT();
        }
        uint16 erc721Idx = infoIdx[erc721].idx;
        uint256 tokenHash = uint256(keccak256(abi.encodePacked(tokenId))) >> 32;
        return WalletLib.NFTId.wrap(erc721Idx | (tokenHash << 16) | ((tokenId >> 240) << 240));
    }

    function _isApprovedOrOwner(address spender, WalletLib.NFTId nftId) internal view returns (bool) {
        WalletLib.Wallet storage p = wallets[msg.sender];
        (uint16 infoIndex, uint256 tokenId) = getNFTData(nftId);
        address collection = erc721Infos[infoIndex].erc721Contract;
        uint16 idx = tokenDataByNFTId[nftId].walletIdx;
        bool isdepositERC721Owner =
            idx < p.nfts.length && WalletLib.NFTId.unwrap(p.nfts[idx]) == WalletLib.NFTId.unwrap(nftId);
        return (isdepositERC721Owner || getApproved(collection, tokenId) == spender);
    }

    // Config functions are handled by SupaConfig
    function _implementation() internal view override returns (address) {
        return supaConfigAddress;
    }
}

