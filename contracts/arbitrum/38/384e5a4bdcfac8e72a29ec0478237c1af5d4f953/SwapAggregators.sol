// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWETH9.sol";
import "./SafeERC20.sol";

/// @title Swap Aggregators Proxy contract
/// @author Matin Kaboli
/// @notice Swaps tokens and send the new token to msg.sender
/// @dev This contract uses Permit2
contract SwapAggregators is Proxy {
    using SafeERC20 for IERC20;

    address public OInch;
    address public Paraswap;

    /// @notice Sets 1Inch and Paraswap variables and approves some tokens to them
    /// @param _permit2 Permit2 contract address
    /// @param _weth WETH9 contract address
    /// @param _oInch 1Inch contract address
    /// @param _paraswap Paraswap contract address
    /// @param _tokens ERC20 tokens that get allowances
    constructor(Permit2 _permit2, IWETH9 _weth, address _oInch, address _paraswap, IERC20[] memory _tokens)
        Proxy(_permit2, _weth)
    {
        OInch = _oInch;
        Paraswap = _paraswap;

        for (uint8 i = 0; i < _tokens.length;) {
            _tokens[i].safeApprove(_oInch, type(uint256).max);
            _tokens[i].safeApprove(_paraswap, type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Swaps using 1Inch protocol
    /// @dev Uses permit2 to receive user tokens
    /// @param _data 1Inch protocol data from API
    /// @param _proxyFee Fee of the proxy contract
    /// @param _permit Permit2 instance
    /// @param _signature Signature used for Permit2
    function swap1Inch(
        bytes calldata _data,
        uint256 _proxyFee,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        (bool success,) = OInch.call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");
    }

    /// @notice Swaps using 1Inch protocol
    /// @dev Uses ETH only
    /// @param _data 1Inch protocol generated data from API
    /// @param _proxyFee Fee of the proxy contract
    function swapETH1Inch(bytes calldata _data, uint256 _proxyFee) external payable {
        (bool success,) = OInch.call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");
    }

    /// @notice Swaps using Paraswap protocol
    /// @dev Uses permit2 to receive user tokens
    /// @param _data Paraswap protocol generated data from API
    /// @param _proxyFee Fee of the proxy contract
    /// @param _permit Permit2 instance
    /// @param _signature Signature used for Permit2
    function swapParaswap(
        bytes calldata _data,
        uint256 _proxyFee,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        (bool success,) = Paraswap.call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");
    }

    /// @notice Swaps using Paraswap protocol
    /// @dev Uses ETH only
    /// @param _data Paraswap protocol generated data from API
    /// @param _proxyFee Fee of the proxy contract
    function swapETHParaswap(bytes calldata _data, uint256 _proxyFee) external payable {
        (bool success,) = Paraswap.call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");
    }

    /// @notice Swaps using 0x protocol
    /// @dev Uses permit2 to receive user tokens
    /// @param _receiveToken The token that user wants to receive
    /// @param _swapTarget Swap target address, used for sending _data
    /// @param _proxyFee Fee of the proxy contract
    /// @param _permit Permit2 instance
    /// @param _signature Signature used for Permit2
    /// @param _data 0x protocol generated data from API
    function swap0x(
        IERC20 _receiveToken,
        address _swapTarget,
        uint24 _proxyFee,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        bytes calldata _data
    ) public payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        (bool success,) = payable(_swapTarget).call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");

        _sweepToken(address(_receiveToken));
    }

    /// @notice Swaps using 0x protocol
    /// @param _receiveToken The token that user wants to receive
    /// @param _swapTarget Swap target address, used for sending _data
    /// @param _proxyFee Fee of the proxy contract
    /// @param _data 0x protocol generated data from API
    function swap0xETH(IERC20 _receiveToken, address _swapTarget, uint24 _proxyFee, bytes calldata _data)
        public
        payable
    {
        (bool success,) = payable(_swapTarget).call{value: msg.value - _proxyFee}(_data);

        require(success, "Failed");

        _sweepToken(address(_receiveToken));
    }

    /// @notice Sets new addresses for 1Inch and Paraswap protocols
    /// @param _oInch Address of the new 1Inch contract
    /// @param _paraswap Address of the new Paraswap contract
    function setDexAddresses(address _oInch, address _paraswap) external onlyOwner {
        OInch = _oInch;
        Paraswap = _paraswap;
    }
}

