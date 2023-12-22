// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./ERC721.sol";
import "./IERC20.sol";
import "./NFTRenderer.sol";

contract HeruCFANFTManagerTest is ERC721 {
    error NotAuthorized();
    error WrongToken();

    event AddLiquidity(
        uint256 indexed tokenId, 
        address depositor, 
        uint256 amount, 
        uint256 futureAmount    
    );

    event RemoveLiquidity(
        uint256 indexed tokenId, 
        address depositor, 
        uint256 amount, 
        uint256 futureAmount    
    );

    struct TokenPosition {
        address depositor;
        uint256 amount;
        uint256 futureAmount;

    }

    uint256 public totalSupply;
    uint256 private nextTokenId;

    address public immutable factory;

    mapping(uint256 => TokenPosition) public positions;

    modifier isApprovedOrOwner(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (
            msg.sender != owner &&
            !isApprovedForAll[owner][msg.sender] &&
            getApproved[tokenId] != msg.sender
        ) revert NotAuthorized();

        _;
    }

    constructor(address factoryAddress)
        ERC721("Heru CFA NFT Position Test", "HeruCFATest")
    {
        factory = factoryAddress;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        TokenPosition memory tokenPosition = positions[tokenId];
        if (tokenPosition.depositor == address(0x00)) revert WrongToken();
        return
            NFTRenderer.render(
                NFTRenderer.RenderParams({
                    owner: tokenPosition.depositor,
                    amount: tokenPosition.amount,
                    futureAmount:tokenPosition.futureAmount
                })
            );
    }

    struct MintParams {
        address depositor;
        uint256 amount;
        uint256 futureAmount;
    }

    function mint(MintParams calldata params) public returns (uint256 tokenId) {

        tokenId = nextTokenId++;
        _mint(params.depositor, tokenId);
        totalSupply++;

        TokenPosition memory tokenPosition = TokenPosition({
            depositor:params.depositor,
            amount:params.amount,
            futureAmount:params.futureAmount
        });

        positions[tokenId] = tokenPosition;

        emit AddLiquidity(tokenId, params.depositor, params.amount, params.futureAmount);
    }

    struct AddLiquidityParams {
        uint256 tokenId;
        uint256 amount;
        uint256 futureAmount;
    }

    function addLiquidity(AddLiquidityParams calldata params)
        public
    {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if (tokenPosition.depositor == address(0x00)) revert WrongToken();
        tokenPosition.amount=params.amount;
        tokenPosition.futureAmount=params.futureAmount;
        positions[params.tokenId] = tokenPosition;

        emit AddLiquidity(params.tokenId, tokenPosition.depositor, tokenPosition.amount, tokenPosition.futureAmount);
    }

    struct RemoveLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
    }

    // TODO: add slippage check
    function removeLiquidity(RemoveLiquidityParams memory params)
        public
        isApprovedOrOwner(params.tokenId)
    {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if (tokenPosition.depositor == address(0x00)) revert WrongToken();


        emit RemoveLiquidity(
            params.tokenId,
            tokenPosition.depositor, 
            tokenPosition.amount, 
            tokenPosition.futureAmount        
        );
    }

    function burn(uint256 tokenId) public isApprovedOrOwner(tokenId) {
        TokenPosition memory tokenPosition = positions[tokenId];
        if (tokenPosition.depositor == address(0x00)) revert WrongToken();

        delete positions[tokenId];
        _burn(tokenId);
        totalSupply--;
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // CALLBACKS
    //
    ////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////


    /*
        Returns position ID within a pool
    */
    function poolPositionKey(TokenPosition memory position)
        internal
        pure
        returns (bytes32 key)
    {
        key = keccak256(
            abi.encodePacked(
                position.depositor,
                position.amount,
                position.futureAmount
            )
        );
    }

    /*
        Returns position ID within the NFT manager
    */
    function positionKey(TokenPosition memory position)
        internal
        pure
        returns (bytes32 key)
    {
        key = keccak256(
            abi.encodePacked(
                position.depositor,
                position.amount,
                position.futureAmount
            )
        );
    }
}

