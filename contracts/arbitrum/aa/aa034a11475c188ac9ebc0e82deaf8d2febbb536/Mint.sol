// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./Strings.sol";
import "./SignatureChecker.sol";

import "./IUniswapV2Router02.sol";

contract Mint is Ownable {
    address public constant BURN = 0x000000000000000000000000000000000000dEaD;

    address public immutable usdt;
    address public immutable token;
    address public immutable router;

    uint256 public mintFee;
    address public mintFeeTo;
    uint256 public harvestFee;
    address public harvestFeeTo;
    address public signer;
    uint256 public countMax;
    uint256 public totalSupply;

    mapping(bytes => bool) public used;

    mapping(address => uint256) public counts;
    mapping(address => uint256) public keys;
    mapping(address => address) public parent;
    mapping(address => uint256) public referralCounts;

    event Minted(
        address indexed account,
        address indexed referral,
        uint256 time,
        uint256 price,
        uint256 amount,
        uint256 timestamp
    );
    event Harvested(address indexed account, uint256 amount, uint256 id, uint256 index);

    error Forbidden();
    error InvalidFee();
    error InvalidSignature();

    constructor(address _usdt, address _token, address _router) {
        usdt = _usdt;
        token = _token;
        router = _router;
        signer = msg.sender;
        countMax = 3;
    }

    function setMintFee(uint256 newMintFee) public onlyOwner {
        mintFee = newMintFee;
    }

    function setMintFeeTo(address newMintFeeTo) public onlyOwner {
        mintFeeTo = newMintFeeTo;
    }

    function setHarvestFee(uint256 newHarvestFee) public onlyOwner {
        harvestFee = newHarvestFee;
    }

    function setHarvestFeeTo(address newHarvestFeeTo) public onlyOwner {
        harvestFeeTo = newHarvestFeeTo;
    }

    function setSigner(address newSigner) public onlyOwner {
        signer = newSigner;
    }

    function setCountMax(uint256 newCountMax) public onlyOwner {
        countMax = newCountMax;
    }

    function mint(
        uint256 time,
        uint256 price,
        uint256 amount,
        bytes memory signature,
        address referral
    ) public payable {
        if (Address.isContract(msg.sender)) revert Forbidden();

        if (counts[msg.sender] >= countMax) revert Forbidden();

        if (mintFee > 0) {
            if (msg.value < mintFee) revert InvalidFee();
            payable(mintFeeTo).transfer(mintFee);
        }

        bytes memory message = abi.encode(time, price, amount);
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length), message)
        );
        if (SignatureChecker.isValidSignatureNow(signer, hash, signature) == false) revert InvalidSignature();

        IERC20(usdt).transferFrom(msg.sender, address(this), price);

        keys[msg.sender]++;

        if (referral != address(0)) {
            parent[msg.sender] = referral;
            referralCounts[referral]++;
            if (referralCounts[referral] % 3 == 0) {
                keys[referral]++;
            }
        }

        IERC20(usdt).approve(router, price);
        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = token;
        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            price,
            0,
            path,
            BURN,
            address(0),
            block.timestamp
        );

        emit Minted(msg.sender, referral, time, price, amount, block.timestamp);
    }

    function harvest(
        address account,
        uint256 amount,
        uint256 id,
        uint256 index,
        uint256 deadline,
        bytes memory signature
    ) public {
        if (block.timestamp > deadline) revert InvalidSignature();
        if (used[signature] == true) revert InvalidSignature();

        bytes memory message = abi.encode(account, amount, id, index, deadline);
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(bytes(message).length), message)
        );
        if (SignatureChecker.isValidSignatureNow(signer, hash, signature) == false) revert InvalidSignature();

        if (harvestFee > 0) {
            IERC20(usdt).transferFrom(account, harvestFeeTo, harvestFee);
        }

        IERC20(token).transfer(account, amount);
        totalSupply += amount;

        emit Harvested(account, amount, id, index);
    }

    function claim(address asset, address to, uint256 amount) public onlyOwner {
        if (asset == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(asset).transfer(to, amount);
        }
    }
}

