// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.11;

import "./ERC20_IERC20.sol";
import "./IBentoBoxMinimal.sol";
import "./IStargateRouter.sol";
import "./IStargateReceiver.sol";
import "./BoringBatchable.sol";
import "./SushiLegacy.sol";
import "./TridentSwap.sol";

contract SushiXSwap is
    IStargateReceiver,
    BoringBatchable,
    SushiLegacy,
    TridentSwap
{
    struct TeleportParams {
        uint16 dstChainId;
        address token;
        uint256 srcPoolId;
        uint256 dstPoolId;
        uint256 amount;
        uint256 amountMin;
        uint256 dustAmount;
        address receiver;
        address to;
        uint256 gas;
    }

    IBentoBoxMinimal public immutable bentoBox;
    IStargateRouter public immutable stargateRouter;

    constructor(IBentoBoxMinimal _bentoBox, IStargateRouter _stargateRouter) {
        stargateRouter = _stargateRouter;
        bentoBox = _bentoBox;
        _bentoBox.registerProtocol();
    }

    function setBentoBoxApproval(
        address user,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bentoBox.setMasterContractApproval(
            user,
            address(this),
            approved,
            v,
            r,
            s
        );
    }

    function approveToStargateRouter(IERC20 token) external {
        token.approve(address(stargateRouter), type(uint256).max);
    }

    function _depositToBentoBox(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share,
        uint256 value
    ) internal {
        bentoBox.deposit{value: value}(token, from, to, amount, share);
    }

    function _transferFromBentoBox(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bentoBox.withdraw(token, from, to, amount, share);
        } else {
            bentoBox.transfer(token, from, to, share);
        }
    }

    function _transferTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (address(token) != address(0)) {
            token.transfer(to, amount);
        } else {
            payable(to).transfer(amount);
        }
    }

    function _teleport(
        TeleportParams memory params,
        uint8[] memory actions,
        uint256[] memory values,
        bytes[] memory datas
    ) internal {
        bytes memory payload = abi.encode(params.to, actions, values, datas);

        stargateRouter.swap{value: address(this).balance}(
            params.dstChainId,
            params.srcPoolId,
            params.dstPoolId,
            payable(msg.sender),
            params.amount != 0
                ? params.amount
                : IERC20(params.token).balanceOf(address(this)),
            params.amountMin,
            IStargateRouter.lzTxObj(
                params.gas,
                params.dustAmount,
                abi.encodePacked(params.receiver)
            ),
            abi.encodePacked(params.receiver),
            payload
        );
    }

    // ACTION_LIST
    uint8 constant SRC_DEPOSIT_TO_BENTOBOX = 0;
    uint8 constant SRC_TRANSFER_FROM_BENTOBOX = 1;
    uint8 constant DST_DEPOSIT_TO_BENTOBOX = 2;
    uint8 constant DST_WITHDRAW_TOKEN = 3;
    uint8 constant TELEPORT = 4;
    uint8 constant LEGACY_SWAP = 5;
    uint8 constant TRIDENT_SWAP = 6;
    uint8 constant DST_WITHDRAW_BENTO = 7;
    uint8 constant MASTER_CONTRACT_APPROVAL = 8;

    function cook(
        uint8[] memory actions,
        uint256[] memory values,
        bytes[] memory datas
    ) public payable {
        for (uint256 i = 0; i < actions.length; i++) {
            uint8 action = actions[i];
            // update for total amounts in contract?
            if (action == MASTER_CONTRACT_APPROVAL) {
                (
                    address user,
                    bool approved,
                    uint8 v,
                    bytes32 r,
                    bytes32 s
                ) = abi.decode(
                        datas[i],
                        (address, bool, uint8, bytes32, bytes32)
                    );

                bentoBox.setMasterContractApproval(
                    user,
                    address(this),
                    approved,
                    v,
                    r,
                    s
                );
            } else if (action == SRC_DEPOSIT_TO_BENTOBOX) {
                (address token, address to, uint256 amount, uint256 share) = abi
                    .decode(datas[i], (address, address, uint256, uint256));
                _depositToBentoBox(
                    token,
                    msg.sender,
                    to,
                    amount,
                    share,
                    values[i]
                );
            } else if (action == SRC_TRANSFER_FROM_BENTOBOX) {
                (
                    address token,
                    address to,
                    uint256 amount,
                    uint256 share,
                    bool unwrapBento
                ) = abi.decode(
                        datas[i],
                        (address, address, uint256, uint256, bool)
                    );
                _transferFromBentoBox(
                    token,
                    msg.sender,
                    to,
                    amount,
                    share,
                    unwrapBento
                );
            } else if (action == DST_DEPOSIT_TO_BENTOBOX) {
                (address token, address to, uint256 amount, uint256 share) = abi
                    .decode(datas[i], (address, address, uint256, uint256));

                if (amount == 0) {
                    amount = IERC20(token).balanceOf(address(this));
                    // left values not updates intentionally
                }

                _transferTokens(IERC20(token), address(bentoBox), amount);

                _depositToBentoBox(
                    token,
                    address(bentoBox),
                    to,
                    amount,
                    share,
                    values[i]
                );
            } else if (action == DST_WITHDRAW_TOKEN) {
                (address token, address to, uint256 amount) = abi.decode(
                    datas[i],
                    (address, address, uint256)
                );
                if (amount == 0) {
                    if (token != address(0)) {
                        amount = IERC20(token).balanceOf(address(this));
                    } else {
                        amount = address(this).balance;
                    }
                }
                _transferTokens(IERC20(token), to, amount);
            } else if (action == DST_WITHDRAW_BENTO) {
                (
                    address token,
                    address to,
                    uint256 amount,
                    uint256 share,
                    bool unwrapBento
                ) = abi.decode(
                        datas[i],
                        (address, address, uint256, uint256, bool)
                    );
                if (amount == 0) {
                    amount = IERC20(token).balanceOf(address(this));
                }
                _transferFromBentoBox(
                    token,
                    address(this),
                    to,
                    amount,
                    share,
                    unwrapBento
                );
            } else if (action == TELEPORT) {
                (
                    TeleportParams memory params,
                    uint8[] memory actionsDST,
                    uint256[] memory valuesDST,
                    bytes[] memory datasDST
                ) = abi.decode(
                        datas[i],
                        (TeleportParams, uint8[], uint256[], bytes[])
                    );

                _teleport(params, actionsDST, valuesDST, datasDST);
            } else if (action == LEGACY_SWAP) {
                (
                    address factory,
                    bytes32 pairCodeHash,
                    uint256 amountIn,
                    uint256 amountOutMin,
                    address[] memory path,
                    address to
                ) = abi.decode(
                        datas[i],
                        (address, bytes32, uint256, uint256, address[], address)
                    );
                bool sendTokens;
                if (amountIn == 0) {
                    IERC20(path[0]).balanceOf(address(this));
                    sendTokens = true;
                }
                _swapExactTokensForTokens(
                    factory,
                    pairCodeHash,
                    amountIn,
                    amountOutMin,
                    path,
                    to,
                    sendTokens
                );
            } else if (action == TRIDENT_SWAP) {
                ExactInputParams memory params = abi.decode(
                    datas[i],
                    (ExactInputParams)
                );

                _exactInput(bentoBox, params, address(this));
            }
        }
    }

    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external override {
        require(
            msg.sender == address(stargateRouter),
            "Caller not Stargate Router"
        );

        (
            address to,
            uint8[] memory actions,
            uint256[] memory values,
            bytes[] memory datas
        ) = abi.decode(payload, (address, uint8[], uint256[], bytes[]));

        try SushiXSwap(payable(this)).cook(actions, values, datas) {} catch (
            bytes memory
        ) {
            IERC20(_token).transfer(to, amountLD);
        }
    }

    receive() external payable {}
}

