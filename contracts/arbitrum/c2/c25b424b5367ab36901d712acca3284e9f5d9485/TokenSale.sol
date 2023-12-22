// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IERC20.sol";
import "./MerkleProof.sol";

contract TokenSale {
    address public multisig;
    uint public tokenSaleStage = 0; // 0 = Omega, 1 = Alpha, 2 = Whitelist
    uint public refPercentage = 1000; //10%
    bytes32[3] public merkleRoots;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint public priceMultiplier = 2; // $0.5/LNDX 1e6 = 5e5 = (x = 1e6 / 5e5) = 2
    mapping(address => uint256) public allocation;
    mapping(address => bool) public contributed;
    address[] public contributors;
    uint public available = 3000000 * 10 ** 6; // LNDX 6 decimals

    event Contribution(uint256 amount, address contributor);
    event Referral(uint256 amount, uint256 refAmount, address contributor, address referrer);

    constructor() {
        multisig = msg.sender;
        merkleRoots[0] = 0x1f2ede652390c98d48f086e75cf059697b65eb6f58199258a061e1eb38f00772;
        merkleRoots[1] = 0x223353dd9538fe9acd7e7469920d5a4a9c83b82a2377246f1c14ea09e43f9353;
        merkleRoots[2] = 0xbaef4c074bdf663e724d3cd4ca9fafa42527b8582c0f30e3998ca4ed8568ce11;
    }

    function checkProof(address _user, bytes32[] calldata _merkleProof) public view returns(bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_user));
        bool result = MerkleProof.verify(_merkleProof, merkleRoots[tokenSaleStage], leaf);
        return result;
    }

    function buyTokens(uint _amountUSDC, bytes32[] calldata _merkleProof, address referrer) external {
        if (tokenSaleStage != 2) {
            require(checkProof(msg.sender, _merkleProof) == true, "Merkle proof does not validate");
        }
        IERC20(usdc).transferFrom(msg.sender, address(this), _amountUSDC);
        if (referrer != address(0) && tokenSaleStage == 2) {
            uint256 refAmount = _amountUSDC / 10000 * refPercentage;
            IERC20(usdc).transfer(referrer, refAmount);
            emit Referral(_amountUSDC, refAmount, msg.sender, referrer);
        }
        uint lndxOut = _amountUSDC * priceMultiplier;
       
        require (available - lndxOut >= 0, "sold out");
        
        available -= lndxOut;

        if (contributed[msg.sender] == false) {
            contributors.push(msg.sender);
        }

        contributed[msg.sender] = true;
        allocation[msg.sender] += lndxOut;

        emit Contribution(_amountUSDC, msg.sender);
    }

    function updateMultisig(address _multisig) external {
        require(msg.sender == multisig, "only multisig has access");
        multisig = _multisig;
    }

    function updateMerkleRoots(uint _tokenSaleStage, bytes32 _omegaRoot, bytes32 _alphaRoot, bytes32 _whitelistRoot) external {
        require(msg.sender == multisig, "only multisig has access");
        tokenSaleStage = _tokenSaleStage;
        merkleRoots[0] = _omegaRoot;
        merkleRoots[1] = _alphaRoot;
        merkleRoots[2] = _whitelistRoot;
    }

    function updatePrice(uint _priceMultiplier) external {
        require(msg.sender == multisig, "only multisig has access");
        priceMultiplier = _priceMultiplier;
    }

     function updateRefPercentage(uint _percentage) external {
        require(msg.sender == multisig, "only multisig has access");
        refPercentage = _percentage;
    }

    function updateTokens(address _usdc) external {
        require(msg.sender == multisig, "only multisig has access");
        usdc = _usdc;
    }

    function reclaimToken(IERC20 token) external {
        require(msg.sender == multisig, "only multisig has access");
        require(address(token) != address(0));
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }
}
