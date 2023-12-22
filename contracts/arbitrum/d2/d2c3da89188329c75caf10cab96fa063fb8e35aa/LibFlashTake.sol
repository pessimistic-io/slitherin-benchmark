// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./ECDSAUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ILiquidityPool.sol";
import "./IReferralManager.sol";
import "./LibSubAccount.sol";
import "./LibOrder.sol";
import "./core_Types.sol";

interface IInternalFlashTaker {
    function internalFlashTake(FlashTakeParam calldata order) external;
}

library LibFlashTake {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // keccak256(abi.encodePacked("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"))
    bytes32 internal constant FLASH_TAKE_DOMAIN_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    // keccak256(bytes("MUX Protocol"))
    bytes32 internal constant FLASH_TAKE_NAME_HASH = 0x095b39c6e1c90d875997697322803685b422ef81f122ae9e1b3fa7d00be00155;
    // keccak256(bytes("v1"))
    bytes32 internal constant FLASH_TAKE_VERSION_HASH =
        0x0984d5efd47d99151ae1be065a709e56c602102f24c1abc4008eb3f815a8d217;
    // keccak256(abi.encodePacked("FlashTake(bytes32 subAccountId,uint96 collateral,uint96 size,uint96 gasFee,bytes32 referralCode,uint8 orderType,uint8 flags,uint8 profitTokenId,uint32 placeOrderTime,uint32 salt)"))
    bytes32 internal constant FLASH_TAKE_TYPE_HASH = 0xd8c31d819b70be06a8d8983e9a7f567c7786030cef350957d3a42d2eb321cc55;

    event FillingFlashTake(uint64 indexed flashTakeSequence);
    event FillFlashTake(
        bytes32 indexed subAccountId,
        uint64 indexed flashTakeSequence,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 gasFee, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        string errorMessage // errorMessage = "" if success
    );

    function flashTake(
        FlashTakeParam[] calldata orders,
        address orderBook,
        uint64 previousFlashTakeSequence,
        mapping(bytes32 => uint64) storage filledFlashTakeOrder
    ) public returns (uint64 newSequence) {
        uint256 orderLength = orders.length;
        newSequence = previousFlashTakeSequence;
        for (uint256 i = 0; i < orderLength; i++) {
            FlashTakeParam calldata order = orders[i];
            newSequence += 1;
            require(order.flashTakeSequence == newSequence, "SEQ"); // invalid SEQuence
            // signature
            {
                address account = LibSubAccount.getSubAccountOwner(order.order.subAccountId);
                (bytes32 flashTakeOrderHash, address recovered) = recoveryFlashTakeSigner(order.order, order.signature);
                require(account == recovered, "712"); // EIP712 signature mismatched
                require(filledFlashTakeOrder[flashTakeOrderHash] == 0, "OID"); // already filled. keep the meaning the same as "can not find this OrderID" in fillPositionOrder
                filledFlashTakeOrder[flashTakeOrderHash] = order.flashTakeSequence; // prevent replay attack
            }
            // trade
            emit FillingFlashTake(order.flashTakeSequence);
            string memory errorMessage;
            try IInternalFlashTaker(orderBook).internalFlashTake(order) {} catch Error(string memory reason) {
                errorMessage = reason;
            } catch (bytes memory) {
                errorMessage = "RVT"; // unknown ReVerT reason
            }
            emit FillFlashTake(
                order.order.subAccountId,
                order.flashTakeSequence,
                order.order.collateral,
                order.order.size,
                order.order.gasFee,
                order.order.profitTokenId,
                order.order.flags,
                errorMessage
            );
        }
    }

    function internalFlashTake(
        FlashTakeParam calldata order,
        ILiquidityPool pool,
        uint256 blockTimestamp,
        uint256 marketOrderTimeout,
        address referralManager
    ) public {
        require(order.order.size != 0, "S=0"); // order Size Is Zero
        require(order.order.orderType == uint8(OrderType.FlashTakePositionOrder), "TYP"); // order TYPe mismatch
        require(blockTimestamp <= order.order.placeOrderTime + marketOrderTimeout, "EXP"); // EXPired
        require((order.order.flags & LibOrder.POSITION_MARKET_ORDER) != 0, "MKT"); // only MarKeT order is supported
        if (order.order.profitTokenId > 0) {
            // note: profitTokenId == 0 is also valid, this only partially protects the function from misuse
            require((order.order.flags & LibOrder.POSITION_OPEN) == 0, "T!0"); // opening position does not need a Token id
        }
        LibSubAccount.DecodedSubAccountId memory account = LibSubAccount.decodeSubAccountId(order.order.subAccountId);
        if (order.order.referralCode != bytes32(0) && referralManager != address(0)) {
            IReferralManager(referralManager).setReferrerCodeFor(account.account, order.order.referralCode);
        }
        if ((order.order.flags & LibOrder.POSITION_OPEN) != 0) {
            // auto deposit
            if (order.order.collateral > 0) {
                IERC20Upgradeable collateral = IERC20Upgradeable(pool.getAssetAddress(account.collateralId));
                collateral.safeTransferFrom(account.account, address(pool), order.order.collateral);
                pool.depositCollateral(order.order.subAccountId, order.order.collateral);
            }
            pool.openPosition(
                order.order.subAccountId,
                order.order.size,
                order.collateralPrice,
                order.assetPrice,
                order.order.gasFee
            );
        } else {
            pool.closePosition(
                order.order.subAccountId,
                order.order.size,
                order.order.profitTokenId,
                order.collateralPrice,
                order.assetPrice,
                order.profitAssetPrice,
                order.order.gasFee
            );
            // auto withdraw
            if (order.order.collateral > 0) {
                pool.withdrawCollateral(
                    order.order.subAccountId,
                    order.order.collateral,
                    order.collateralPrice,
                    order.assetPrice
                );
            }
            if ((order.order.flags & LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY) != 0) {
                (uint96 remainingCollateral, uint96 size, , , ) = pool.getSubAccount(order.order.subAccountId);
                if (size == 0 && remainingCollateral > 0) {
                    pool.withdrawAllCollateral(order.order.subAccountId);
                }
            }
        }
    }

    /**
     * Recovery FlashTake signer from signature.
     *
     * @param req FlashTake order
     * @param signature {bytes32 r}{bytes32 s}{uint8 v}
     *        if v is 27 or 28, treat signature as EIP712
     *        if v is 31 or 32, treat signature as eth_sign
     */
    function recoveryFlashTakeSigner(FlashTakeEIP712 calldata req, bytes calldata signature)
        public
        view
        returns (bytes32 eip712Hash, address signer)
    {
        bytes32 typedMessageHash = keccak256(
            abi.encode(
                FLASH_TAKE_TYPE_HASH,
                req.subAccountId,
                req.collateral,
                req.size,
                req.gasFee,
                req.referralCode,
                req.orderType,
                req.flags,
                req.profitTokenId,
                req.placeOrderTime,
                req.salt
            )
        );
        eip712Hash = ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), typedMessageHash);
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        if (v > 30) {
            signer = ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(eip712Hash), v - 4, r, s);
        } else {
            signer = ECDSAUpgradeable.recover(eip712Hash, v, r, s);
        }
    }

    function _domainSeparatorV4() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    FLASH_TAKE_DOMAIN_HASH,
                    FLASH_TAKE_NAME_HASH,
                    FLASH_TAKE_VERSION_HASH,
                    block.chainid,
                    address(this)
                )
            );
    }

    function _splitSignature(bytes memory signature)
        private
        pure
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        require(signature.length == 65, "RSV"); // only {r}{s}{v} is supported
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }
}

