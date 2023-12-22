// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./HinkalBase.sol";
import "./IExternalAction.sol";
import "./ITransactHook.sol";
import "./IVerifier.sol";
import "./IHinkal.sol";
import "./HinkalMigrator.sol";

contract Hinkal is IHinkal, HinkalBase, HinkalMigrator {
    IVerifier public immutable verifier;

    mapping(uint256 => address) internal externalActionMap;

    constructor(ConstructorArgs memory args)
        HinkalBase(
            args.poseidon4Address,
            args.merkleTreeAddress,
            args.accessTokenAddress,
            args.erc20TokenRegistryAddress,
            args.relayStoreAddress
        )
    {
        verifier = IVerifier(args.verifierFacadeAddress);
    }

    function registerExternalAction(uint256 externalActionId, address externalActionAddress)
    public
    onlyOwner
    {
        externalActionMap[externalActionId] = externalActionAddress;
        emit ExternalActionRegistered(externalActionId, externalActionAddress);
    }

    function removeExternalAction(uint256 externalActionId)
    public
    onlyOwner
    {
        delete externalActionMap[externalActionId];
        emit ExternalActionRemoved(externalActionId);
    }

    function buildVerifierId(
        uint16 nullifierAmount,
        uint16 outputAmount,
        uint256 externalActionId
    )
    internal
    pure
    returns (uint256)
    {
        return uint256(keccak256(abi.encode(nullifierAmount, outputAmount, externalActionId != 0)));
    }

    function buildCircomData(
        uint256 externalActionId,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount
    )
        internal
        pure
        returns (CircomData memory circomData, uint256[] memory inputNullifiers)
    {
        inputNullifiers = new uint256[](nullifierAmount);
        uint16 inputIdx = 0;

        if (externalActionId == 0) {

            circomData.externalActionId = 0;

            circomData.rootHashHinkal = input[inputIdx++];
            uint256 publicAmountFromCircom = input[inputIdx++];
            int256 publicAmount;
            // 1) Case of Deposit when public amount > 0
            if (publicAmountFromCircom <= P / 2) {
                publicAmount = int256(publicAmountFromCircom);
            }
            // 2) Case of Withdraw when public amount < 0
            else if (publicAmountFromCircom > P / 2) {
                uint256 dif = P - publicAmountFromCircom;
                publicAmount = -1 * int256(dif);
            }
            circomData.publicAmount = publicAmount;
            circomData.recipientAddress = address(uint160(input[inputIdx++]));
            circomData.inErc20TokenAddress = address(uint160(input[inputIdx++]));

            for (uint16 i = 0; i < nullifierAmount; i++) {
                inputNullifiers[i] = input[inputIdx  + i];
            }
            inputIdx += nullifierAmount;

            circomData.outCommitments = new uint256[](outputAmount);
            for (uint16 i = 0; i < outputAmount; i++) {
                circomData.outCommitments[i] = input[inputIdx  + i];
            }
            inputIdx += outputAmount;

            circomData.rootHashAccessToken = input[inputIdx++];
            circomData.relay = address(uint160(input[inputIdx++]));
            circomData.relayFee = input[inputIdx];
        } else {
            circomData.rootHashHinkal = input[inputIdx++];
            circomData.inErc20TokenAddress = address(uint160(input[inputIdx++]));

            for (uint16 i = 0; i < nullifierAmount; i++) {
                inputNullifiers[i] = input[inputIdx  + i];
            }
            inputIdx += nullifierAmount;

            circomData.inAmount = input[inputIdx++];
            circomData.outAmount = input[inputIdx++];
            circomData.outErc20TokenAddress = address(
                uint160(input[inputIdx++])
            );

            circomData.outCommitments = new uint256[](outputAmount);
            for (uint16 i = 0; i < outputAmount; i++) {
                circomData.outCommitments[i] = input[inputIdx  + i];
            }
            inputIdx += outputAmount;

            circomData.rootHashAccessToken = input[inputIdx++];
            circomData.externalActionId = uint256(input[inputIdx++]);
            circomData.externalActionMetadataHash = uint256(input[inputIdx++]);
            circomData.relay = address(uint160(input[inputIdx++]));
            circomData.relayFee = input[inputIdx];

        }
        return (circomData, inputNullifiers);
    }

    function transact(
        bytes[] memory encryptedOutputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount
    ) public payable nonReentrant {
        _transact(
            encryptedOutputs,
            a,
            b,
            c,
            input,
            nullifierAmount,
            outputAmount,
            0,
            '',
            address(0),
            ''
        );
    }

    function transactWithExternalAction(
        bytes[] memory encryptedOutputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount,
        uint256 externalActionId,
        bytes memory externalActionMetadata
    ) public payable nonReentrant {
        require(externalActionId != 0, 'externalActionId is missing');
        _transact(
            encryptedOutputs,
                a,
                b,
                c,
                input,
                nullifierAmount,
                outputAmount,
                externalActionId,
                externalActionMetadata,
                address(0),
                ''
        );
    }

    function transactWithHook(
        bytes[] memory encryptedOutputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount,
        address hookContract,
        bytes memory hookMetadata
    ) public payable nonReentrant {
        require(hookContract != address(0), 'hookContract is missing');
        _transact(
            encryptedOutputs,
                a,
                b,
                c,
                input,
                nullifierAmount,
                outputAmount,
                0,
                '',
                hookContract,
                hookMetadata
        );
    }

    function transactWithExternalActionAndHook(
        bytes[] memory encryptedOutputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount,
        uint256 externalActionId,
        bytes memory externalActionMetadata,
        address hookContract,
        bytes memory hookMetadata
    ) public payable nonReentrant {
        require(externalActionId != 0, 'externalActionId is missing');
        require(hookContract != address(0), 'hookContract is missing');
        _transact(
            encryptedOutputs,
            a,
            b,
            c,
            input,
            nullifierAmount,
            outputAmount,
            externalActionId,
            externalActionMetadata,
            hookContract,
            hookMetadata
        );
    }

    function _transact(
        bytes[] memory encryptedOutputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory input,
        uint16 nullifierAmount,
        uint16 outputAmount,
        uint256 externalActionId,
        bytes memory externalActionMetadata,
        address hookContract,
        bytes memory hookMetadata
    ) internal {
        uint256 verifierId = buildVerifierId(nullifierAmount, outputAmount, externalActionId);
        require(verifier.verifyProof(a, b, c, input, verifierId), "Invalid Proof");
        (CircomData memory circomData, uint256[] memory inputNullifiers) = buildCircomData(
            externalActionId,
            input,
            nullifierAmount,
            outputAmount
        );

        // Root Hash Validation
        require(
            merkleTree.rootHashExists(circomData.rootHashHinkal),
            "Invalid merkle tree root"
        );
        require(
            accessToken.rootHashExists(circomData.rootHashAccessToken),
            "Access Token not minted"
        );

        for (uint256 i = 0; i < inputNullifiers.length; i++) {
            require(!nullifiers[inputNullifiers[i]], "Nullifier cannot be reused");
            nullifiers[inputNullifiers[i]] = true;
            emit Nullified(inputNullifiers[i]);
        }

        if (externalActionId == 0) {
            _internalTransact(circomData);
        } else {
            _internalRunExternalAction(
                circomData,
                externalActionId,
                externalActionMetadata
            );
        }

        insertCommitments(circomData.outCommitments, encryptedOutputs);

        if (hookContract != address(0)) {
            ITransactHook transactHook = ITransactHook(hookContract);
            transactHook.afterTransact(circomData, hookMetadata);
        }
    }

    function _internalTransact(CircomData memory circomData)
        private
        checkTokenRegistry(
            circomData.inErc20TokenAddress,
            circomData.inErc20TokenAddress,
            circomData.publicAmount
        )
    {

        if (circomData.relay != address(0)) {
            require(msg.sender == circomData.relay, "Unauthorized relay 1");
            require(
                relayStore.isRelayInList(circomData.relay),
                "Unauthorized relay 2"
            );
        }

        //Payments Processing
        // 1) Case of Deposit when public amount > 0
        if (circomData.publicAmount > 0) {
            transferERC20TokenFromOrCheckETH(
                circomData.inErc20TokenAddress,
                msg.sender,
                address(this),
                uint256(circomData.publicAmount)
            );
        }
        // 2) Case of Withdraw when public amount < 0
        else if (circomData.publicAmount < 0) {
            uint256 relayFee = 0;
            if (circomData.relay != address(0)) {
                int256 amountWithoutFee = (int256(10000) - int8(relayStore.relayPercentage())) *
                    circomData.publicAmount / 10000;
                relayFee = uint256(-(circomData.publicAmount - amountWithoutFee));
                require(
                    circomData.relayFee == relayFee,
                    "relay Fee Mismatch"
                );
                transferERC20TokenOrETH(
                    circomData.inErc20TokenAddress,
                    circomData.relay,
                    relayFee
                );
            }
            transferERC20TokenOrETH(
                circomData.inErc20TokenAddress,
                circomData.recipientAddress,
                uint256(-circomData.publicAmount) - relayFee
            );
        }

        emit NewTransaction(
            block.timestamp,
            circomData.inErc20TokenAddress,
            circomData.publicAmount
        );
    }

    function _internalRunExternalAction(
        CircomData memory circomData,
        uint256 externalActionId,
        bytes memory externalActionMetadata
    )
        internal
        checkTokenRegistry(
            circomData.outErc20TokenAddress,
            circomData.inErc20TokenAddress,
            int256(circomData.inAmount)
        )
    {
        require(externalActionId == circomData.externalActionId, "Wrong externalActionId");
        require(
            hashMetadata(externalActionMetadata) == circomData.externalActionMetadataHash,
            "externalActionMetadata hash mismatch"
        );

        address externalActionAddress = externalActionMap[externalActionId];

        require(externalActionAddress != address(0), "Unknown externalAction");

        if (circomData.inAmount > 0) {
            transferERC20TokenOrETH(
                circomData.inErc20TokenAddress,
                externalActionAddress,
                circomData.inAmount
            );
        }

        uint256 initialBalance = getERC20OrETHBalance(circomData.outErc20TokenAddress);

        // TODO: Can we send value here instead of transferring ETH?
        IExternalAction(externalActionAddress).runAction(circomData, externalActionMetadata);

        uint256 totalReceived = getERC20OrETHBalance(circomData.outErc20TokenAddress) -  initialBalance;
        require(
            totalReceived >= circomData.outAmount,
            "received fewer amount of tokens than expected"
        );

        if (circomData.relay != address(0)) {
            require(
                msg.sender == circomData.relay,
                "Unauthorized relay 1"
            );
            require(
                relayStore.isRelayInList(circomData.relay),
                "Unauthorized relay 2"
            );
            if (totalReceived > circomData.outAmount) {
                transferERC20TokenOrETH(
                    circomData.outErc20TokenAddress,
                    circomData.relay,
                    totalReceived - circomData.outAmount
                );
            }
        }

        // Todo: Where should the extra amount of tokens go?
    }

    function migrate(CircomData memory circomData, MigrateData memory migrateData) internal override {
        insertCommitment(
            poseidon4.poseidon([
                uint256(-1 * circomData.publicAmount),
                uint256(uint160(circomData.inErc20TokenAddress)),
                migrateData.shieldedPublicKey,
                migrateData.blinding
            ]),
            migrateData.encryptedOutput
        );
    }

    function insertCommitments(
        uint256[] memory outCommitments,
        bytes[] memory encryptedOutputs
    )
    internal
    {
        for (uint16 i = 0; i < outCommitments.length; i++) {
            insertCommitment(outCommitments[i], encryptedOutputs[i]);
        }
    }

    function hashMetadata(bytes memory metadata)
        public
        view
        returns (uint256)
    {
        return uint256(keccak256(metadata)) % P;
    }
}

