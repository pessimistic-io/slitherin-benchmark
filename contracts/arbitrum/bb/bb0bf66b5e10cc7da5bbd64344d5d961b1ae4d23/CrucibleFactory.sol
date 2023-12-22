// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IBurnable.sol";
import "./IFerrumDeployer.sol";
import "./ICrucibleFactory.sol";
import "./CrucibleTokenDeployer.sol";
import "./NoDelegateCall.sol";
import "./StringLib.sol";
import "./WithAdmin.sol";

/// @title Factory for generating crucible tokens
/// @author Ferrum Network
contract CrucibleFactory is
    CrucibleTokenDeployer,
    NoDelegateCall,
    ICrucibleFactory,
    WithAdmin
{
    uint64 constant MAX_FEE = 10000;
    address public immutable override router;
    mapping(bytes32 => address) private crucible;

    event CrucibleCreated(
        address token,
        address baseToken,
        uint256 feeOnTransferX10000,
        uint256 feeOnWithdrawX10000
    );

    constructor() {
        (router) = abi.decode(
            IFerrumDeployer(msg.sender).initData(),
            (address)
        );
    }

    /**
    @notice Returns the crucible address
    @param baseToken The base token address
    @param feeOnTransferX10000 Fee on transfer rate per 10k
    @param feeOnWithdrawX10000 Fee on withdraw rate per 10k
    @return The crucible address if any
     */
    function getCrucible(
        address baseToken,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) external view override returns (address) {
        return
            crucible[
                crucibleKey(baseToken, feeOnTransferX10000, feeOnWithdrawX10000)
            ];
    }

    /**
    @notice Creates a crucible
    @param baseToken The base token address
    @param feeOnTransferX10000 Fee on transfer rate per 10k
    @param feeOnWithdrawX10000 Fee on withdraw rate per 10k
    @return token The created crucible address
     */
    function createCrucible(
        address baseToken,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) external noDelegateCall returns (address token) {
        return
            _createCrucible(
                baseToken,
                safeName(baseToken),
                safeSymbol(baseToken),
                feeOnTransferX10000,
                feeOnWithdrawX10000
            );
    }

    /**
    @notice Creates a crucible directly
    @dev To be used only by contract admin in case normal crucible generation
         cannot succeed.
    @return token The created crucible token address
     */
    function createCrucibleDirect(
        address baseToken,
        string memory name,
        string memory symbol,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) external onlyAdmin returns (address token) {
        bytes32 key = validateCrucible(
            baseToken,
            name,
            symbol,
            feeOnTransferX10000,
            feeOnWithdrawX10000
        );
        return
            _createCrucibleWithName(
                key,
                baseToken,
                name,
                symbol,
                feeOnTransferX10000,
                feeOnWithdrawX10000
            );
    }

    /**
    @notice Tokens accumulated in the factory can be burned by anybody.
    @param token The token address
     */
    function burn(address token
    ) external {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IBurnable(token).burn(amount);
    }

    /**
     @notice Creats a crucible
     @param baseToken The base token
     @param name The name
     @param symbol The symbol
     @param feeOnTransferX10000 Fee on transfer over 10k
     @param feeOnWithdrawX10000 Fee on withdraw over 10k
     @return token The crucible token address
     */
    function _createCrucible(
        address baseToken,
        string memory name,
        string memory symbol,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) internal returns (address token) {
        bytes32 key = validateCrucible(
            baseToken,
            name,
            symbol,
            feeOnTransferX10000,
            feeOnWithdrawX10000
        );
        string memory feeOnT = StringLib.uint2str(feeOnTransferX10000);
        string memory feeOnW = StringLib.uint2str(feeOnWithdrawX10000);
        string memory cName = string(
            abi.encodePacked("Crucible: ", name, " ", feeOnT, "X", feeOnW)
        );
        string memory cSymbol = string(
            abi.encodePacked(symbol, feeOnT, "X", feeOnW)
        );
        token = _createCrucibleWithName(
            key,
            baseToken,
            cName,
            cSymbol,
            feeOnTransferX10000,
            feeOnWithdrawX10000
        );
    }

    /**
     @notice Validates crucible parameters
     @param baseToken The base token
     @param name The name
     @param symbol The symbol
     @param feeOnTransferX10000 Fee on transfer over 10k
     @param feeOnWithdrawX10000 Fee on withdraw over 10k
     */
    function validateCrucible(
        address baseToken,
        string memory name,
        string memory symbol,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) internal view returns (bytes32 key) {
        require(bytes(name).length != 0, "CF: name is required");
        require(bytes(symbol).length != 0, "CF: symbol is required");
        require(
            feeOnTransferX10000 != 0 || feeOnWithdrawX10000 != 0,
            "CF: at least one fee is required"
        );
        require(feeOnTransferX10000 < MAX_FEE, "CF: fee too high");
        require(feeOnWithdrawX10000 < MAX_FEE, "CF: fee too high");
        key = crucibleKey(baseToken, feeOnTransferX10000, feeOnWithdrawX10000);
        require(crucible[key] == address(0), "CF: already exists");
    }

    /**
     @notice Creates a crucible wit the given name
     @param key The crucible key
     @param baseToken The base token
     @param cName The name
     @param cSymbol The symbol
     @param feeOnTransferX10000 Fee on transfer over 10k
     @param feeOnWithdrawX10000 Fee on withdraw over 10k
     */
    function _createCrucibleWithName(
        bytes32 key,
        address baseToken,
        string memory cName,
        string memory cSymbol,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) internal returns (address token) {
        token = deploy(
            address(this),
            baseToken,
            feeOnTransferX10000,
            feeOnWithdrawX10000,
            cName,
            cSymbol
        );
        crucible[key] = token;
        emit CrucibleCreated(
            token,
            baseToken,
            feeOnTransferX10000,
            feeOnWithdrawX10000
        );
    }

    /**
     @notice Returns a name or default
     @param token The token
     @return The name
     */
    function safeName(address token
    ) internal view returns (string memory) {
        (bool succ, bytes memory data) = token.staticcall(
            abi.encodeWithSignature(("name()"))
        );
        if (succ) {
            return abi.decode(data, (string));
        } else {
            return "Crucible";
        }
    }

    /**
     @notice returns the symbol or default
     @param token The token
     @return The symbol
     */
    function safeSymbol(address token
    ) internal view returns (string memory) {
        (bool succ, bytes memory data) = token.staticcall(
            abi.encodeWithSignature(("symbol()"))
        );
        require(succ, "CF: Token has no symbol");
        return abi.decode(data, (string));
    }

    /**
     @notice Creates a key for crucible
     @param baseToken The base token
     @param feeOnTransferX10000 Fee on transfer over 10k
     @param feeOnWithdrawX10000 Fee on withdraw over 10k
     @return The key
     */
    function crucibleKey(
        address baseToken,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    baseToken,
                    feeOnTransferX10000,
                    feeOnWithdrawX10000
                )
            );
    }
}

