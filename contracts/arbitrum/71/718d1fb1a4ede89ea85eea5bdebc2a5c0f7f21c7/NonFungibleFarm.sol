pragma solidity ^0.8.17;
import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./IERC1155.sol";

/**
 * Fren Flow:
 * NFT's are deposited into this contract, having some Price as `points` associated to them.
 * In order to claim an NFT, the fren must have sufficient `points` to reach Price threshold.
 * To increase `points` balance, fren must deposit lp tokens to this contract.
 * `points` balance increases dynamically with each passing second allowing fren to Farm NFTs!
 *
 */
/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw an error.
 * Based off of https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol.
 */
library SafeMath {
    /*
     * Internal functions
     */

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract NonFungibleFarm is Ownable {
    using SafeMath for uint256;

    struct FrenInfo {
        uint256 amount; // current staked LP
        uint256 lastUpdateAt; // unix timestamp for last details update (when pointsDebt calculated)
        uint256 pointsDebt; // total points collected before latest deposit
    }

    struct NFTInfo {
        address contractAddress;
        uint256 id; // NFT id
        uint256 remaining; // NFTs remaining to farm
        uint256 price; // points required to claim NFT
    }

    uint256 public emissionRate; // points generated per LP token per second staked

    NFTInfo[] public nftInfo;
    mapping(address => FrenInfo) public frenInfo;
    mapping(uint256 => IERC20) public lpTokens;
    uint256 public decimals = 10 ** 18;
    uint256 public adjust = 1;

    constructor(uint256 _emissionRate, IERC20 _lpToken) public {
        emissionRate = _emissionRate;
        lpTokens[0] = _lpToken;
    }

    function changePrice(uint256 id, uint256 _price) external onlyOwner {
        nftInfo[id].price = _price;
    }

    function changeLP(uint256 id, IERC20 _lpToken) external onlyOwner {
        lpTokens[id] = _lpToken;
    }

    function changeEmmisions(uint256 _emissionRate, uint256 _adjust) external onlyOwner {
        emissionRate = _emissionRate;
        adjust = _adjust;
    }

    function addNFT(
        address contractAddress, // Only ERC-1155 NFT Supported!
        uint256 id,
        uint256 total, // amount of NFTs deposited to farm (need to approve before)
        uint256 price
    ) external onlyOwner {
        IERC1155(contractAddress).safeTransferFrom(msg.sender, address(this), id, total, "");
        nftInfo.push(NFTInfo({contractAddress: contractAddress, id: id, remaining: total, price: price}));
    }

    function deposit(uint256 id, uint256 _amount) external {
        lpTokens[id].transferFrom(msg.sender, address(this), _amount);

        FrenInfo storage fren = frenInfo[msg.sender];

        // already deposited before
        if (fren.amount != 0) {
            fren.pointsDebt = pointsBalance(msg.sender);
        }
        fren.amount = fren.amount.add(_amount);
        fren.lastUpdateAt = block.timestamp;
    }

    // claim nft if points threshold reached
    function claim(uint256 _nftIndex, uint256 _quantity) public {
        NFTInfo storage nft = nftInfo[_nftIndex];
        require(nft.remaining > 0, "All NFTs farmed");
        require(pointsBalance(msg.sender) >= nft.price.mul(_quantity), "Insufficient Points");
        FrenInfo storage fren = frenInfo[msg.sender];

        // deduct points
        fren.pointsDebt = pointsBalance(msg.sender).sub(nft.price.mul(_quantity));
        fren.lastUpdateAt = block.timestamp;

        // transfer nft
        IERC1155(nft.contractAddress).safeTransferFrom(address(this), msg.sender, nft.id, _quantity, "");

        nft.remaining = nft.remaining.sub(_quantity);
    }

    function claimMultiple(uint256[] calldata _nftIndex, uint256[] calldata _quantity) external {
        require(_nftIndex.length == _quantity.length, "Incorrect array length");
        for (uint64 i = 0; i < _nftIndex.length; i++) {
            claim(_nftIndex[i], _quantity[i]);
        }
    }

    // claim random nft's from available balance
    function claimRandom() public {
        for (uint64 i; i < nftCount(); i++) {
            NFTInfo storage nft = nftInfo[i];
            uint256 userBalance = pointsBalance(msg.sender);
            uint256 maxQty = userBalance.div(nft.price); // max quantity of nfts fren can claim
            if (nft.remaining > 0 && maxQty > 0) {
                if (maxQty <= nft.remaining) {
                    claim(i, maxQty);
                } else {
                    claim(i, nft.remaining);
                }
            }
        }
    }

    function withdraw(uint256 id, uint256 _amount) public {
        FrenInfo storage fren = frenInfo[msg.sender];
        require(fren.amount >= _amount, "Insufficient staked");

        // update frenInfo
        fren.pointsDebt = pointsBalance(msg.sender);
        fren.amount = fren.amount.sub(_amount);
        fren.lastUpdateAt = block.timestamp;

        lpTokens[id].transfer(msg.sender, _amount);
    }

    // claim random NFTs and withdraw all LP tokens
    function exit(uint256 id) external {
        claimRandom();
        withdraw(id, frenInfo[msg.sender].amount);
    }

    function pointsBalance(address userAddress) public view returns (uint256) {
        FrenInfo memory fren = frenInfo[userAddress];
        return fren.pointsDebt.add(_unDebitedPoints(fren));
    }

    function _unDebitedPoints(FrenInfo memory fren) internal view returns (uint256) {
        return (block.timestamp).sub(fren.lastUpdateAt).mul(emissionRate).mul(fren.amount).div(decimals).div(adjust);
    }

    function nftCount() public view returns (uint256) {
        return nftInfo.length;
    }

    // required function to allow receiving ERC-1155
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }
}

