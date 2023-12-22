
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";


error IncorrectPrice();

/**
 * @notice Purchase tokens required for the Arbitrum guild.xyz roles
 * @notice https://guild.xyz/arbitrum
 * @notice Disclaimer: PURCHASE DOES NOT GAURANTEE ARBITRUM AIRDROP
 */
contract ArbitrumBundle is Ownable, ReentrancyGuard {
    using Address for address;

    IERC20[] public tokens;
    uint256[] public amounts;
    uint256 public price = 0.02 ether;

    constructor() {
        // DBL
        tokens.push(IERC20(0xd3f1Da62CAFB7E7BC6531FF1ceF6F414291F03D3));
        amounts.push(0.01 ether);

        // DPX
        tokens.push(IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55));
        amounts.push(0.0001 ether);

        // LPT
        tokens.push(IERC20(0x289ba1701C2F088cf0faf8B3705246331cB8A839));
        amounts.push(0.001 ether);

        // PLS
        tokens.push(IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F));
        amounts.push(0.001 ether);

        // MAGIC
        tokens.push(IERC20(0x539bdE0d7Dbd336b79148AA742883198BBF60342));
        amounts.push(0.001 ether);

        // LINK
        tokens.push(IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4));
        amounts.push(0.001 ether);

        // UMAMI
        tokens.push(IERC20(0x1622bF67e6e5747b81866fE0b85178a93C7F86e3));
        amounts.push(1000000);

        // MYC
        tokens.push(IERC20(0xC74fE4c715510Ec2F8C61d70D397B32043F55Abe));
        amounts.push(0.01 ether);

        // VSTA
        tokens.push(IERC20(0xa684cd057951541187f288294a1e1C2646aA2d24));
        amounts.push(0.01 ether);

        // JONES
        tokens.push(IERC20(0x10393c20975cF177a3513071bC110f7962CD67da));
        amounts.push(0.001 ether);

        // SPA
        tokens.push(IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B));
        amounts.push(0.01 ether);

        // GMX
        tokens.push(IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a));
        amounts.push(0.001 ether);

        // SYN
        tokens.push(IERC20(0x080F6AEd32Fc474DD5717105Dba5ea57268F46eb));
        amounts.push(0.01 ether);

        // HOP-LP-ETH
        tokens.push(IERC20(0x59745774Ed5EfF903e615F5A2282Cae03484985a));
        amounts.push(0.01 ether);

        // BRC
        tokens.push(IERC20(0xB5de3f06aF62D8428a8BF7b4400Ea42aD2E0bc53));
        amounts.push(0.01 ether);

        // SWPR
        tokens.push(IERC20(0xdE903E2712288A1dA82942DDdF2c20529565aC30));
        amounts.push(0.01 ether);
    }

    /**
     * @notice In case there's a need to add more tokens
     * @param token New token to add to bundle
     * @param amount Amount required for guild role
     */
    function addToken(IERC20 token, uint256 amount) external onlyOwner {
        tokens.push(token);
        amounts.push(amount);
    }

    /**
     * @notice Set the price of the bundle incase prices change wildly
     * @param _price Price to purchase a bundle of tokens
     */
    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    /**
     * @notice Purchase a bundle of tokens required for all Arbitrum guild.xyz roles
     */
    function purchaseBundle() external payable nonReentrant {
        if (msg.value != price) revert IncorrectPrice();

        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength;) {
            tokens[i].transfer(msg.sender, amounts[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice Withdraw all tokens from the contract
     */
    function withdrawAllTokens() external onlyOwner {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength;) {
            tokens[i].transfer(msg.sender, tokens[i].balanceOf(address(this)));
            unchecked { ++i; }
        }
    }

    /**
     * @notice Withdraw all ETH from the contract
     */
    function withdrawETH() external onlyOwner {
        Address.sendValue(payable(msg.sender), address(this).balance);
    }
}
