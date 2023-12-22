// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./LiquidityToken.sol";
import "./ILiquidityTokenFactory.sol";
import "./Ownable.sol";

/*                                                *\
 *                ,.-"""-.,                       *
 *               /   ===   \                      *
 *              /  =======  \                     *
 *           __|  (o)   (0)  |__                  *
 *          / _|    .---.    |_ \                 *
 *         | /.----/ O O \----.\ |                *
 *          \/     |     |     \/                 *
 *          |                   |                 *
 *          |                   |                 *
 *          |                   |                 *
 *          _\   -.,_____,.-   /_                 *
 *      ,.-"  "-.,_________,.-"  "-.,             *
 *     /          |       |  ╭-╮     \            *
 *    |           l.     .l  ┃ ┃      |           *
 *    |            |     |   ┃ ╰━━╮   |           *
 *    l.           |     |   ┃ ╭╮ ┃  .l           *
 *     |           l.   .l   ┃ ┃┃ ┃  | \,         *
 *     l.           |   |    ╰-╯╰-╯ .l   \,       *
 *      |           |   |           |      \,     *
 *      l.          |   |          .l        |    *
 *       |          |   |          |         |    *
 *       |          |---|          |         |    *
 *       |          |   |          |         |    *
 *       /"-.,__,.-"\   /"-.,__,.-"\"-.,_,.-"\    *
 *      |            \ /            |         |   *
 *      |             |             |         |   *
 *       \__|__|__|__/ \__|__|__|__/ \_|__|__/    *
\*                                                 */

error DeployerAlreadySet();
error DeployerAlreadyUnset();
error NotAuthorizedDeployer();
error AddressMismatch(address expected, address actual);

contract LiquidityTokenFactory is ILiquidityTokenFactory, Ownable {
    /// @dev Mapping from address to whether it can deploy tokens.
    mapping(address => bool) public deployers;

    event DeployerSet(address deployer);
    event DeployerUnset(address deployer);

    modifier onlyDeployer() {
        if (!deployers[msg.sender]) {
            revert NotAuthorizedDeployer();
        }
        _;
    }

    function setDeployer(address account) external onlyOwner {
        if (deployers[account]) {
            revert DeployerAlreadySet();
        }
        deployers[account] = true;
        emit DeployerSet(account);
    }

    function unsetDeployer(address account) external onlyOwner {
        if (!deployers[account]) {
            revert DeployerAlreadyUnset();
        }
        deployers[account] = false;
        emit DeployerUnset(account);
    }

    function deploy(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        address precomputedAddress
    ) external override onlyDeployer returns (address) {
        LiquidityToken token = new LiquidityToken{salt: salt}(name, symbol);
        address tokenAddress = address(token);
        if (precomputedAddress != tokenAddress) {
            revert AddressMismatch(precomputedAddress, tokenAddress);
        }
        token.transferOwnership(msg.sender);
        return tokenAddress;
    }

    function computeAddress(
        string calldata tokenName,
        string calldata tokenSymbol,
        bytes32 salt
    ) external view override returns (address) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(LiquidityToken).creationCode,
                abi.encode(tokenName, tokenSymbol)
            )
        );
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                salt,
                                bytecodeHash
                            )
                        )
                    )
                )
            );
    }
}

