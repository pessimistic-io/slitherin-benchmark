pragma solidity 0.8.17;

import "./IERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC1155Holder.sol";
import "./ReentrancyGuard.sol";

contract LamboLiquidityV2 is Ownable, Pausable, ERC1155Holder, ReentrancyGuard {
    IERC1155 os = IERC1155(0x495f947276749Ce646f68AC8c248420045cb7b5e);

    uint256 salePrice = .012 ether;
    uint256 buyPrice = .02 ether;
    uint256 swapPrice = .002 ether;
    uint256 maxSwapPrice = .01 ether;

    uint256 mask = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000FFFFFFFFF;
    uint256 maskedPunkValue = 0xC0C8D886B92A811E8E41CB6AB5144E44DBBFBFA3000000000000000000000001;

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getPrices() external returns (uint256 buy, uint256 sell, uint256 swap, uint256 maxSwap) {
        buy = buyPrice;
        sell = salePrice;
        swap = swapPrice;
        maxSwap = maxSwapPrice;
    }

    function isPunk(uint256 tokenId) public returns (bool) {
        return ((tokenId ^ mask) == maskedPunkValue);
    }

    function sellPunk(uint256[] memory osTokenIds) external whenNotPaused nonReentrant {
        uint256 issuedRefund = salePrice * osTokenIds.length;
        require(address(this).balance >= issuedRefund, "not enough to issue refund");
        
        uint256 osTokenId;
        for(uint256 i; i < osTokenIds.length; i = uncheckedInc(i)) {
            osTokenId = osTokenIds[i];            
            require(isPunk(osTokenId), "Not a punk");
            os.safeTransferFrom(msg.sender, address(this), osTokenId, 1, '');        
        }
        payable(msg.sender).call{value: issuedRefund}('');
        emit SoldPunk(msg.sender, osTokenIds);
    }
    // sent ether equivalent to price * n. 
    function buyPunk(uint256[] memory osTokenIds) external payable whenNotPaused nonReentrant {
        require(msg.value == buyPrice * osTokenIds.length);

        uint256 osTokenId;
        for(uint256 i; i < osTokenIds.length; i = uncheckedInc(i)) {
            osTokenId = osTokenIds[i];
            require(isPunk(osTokenId), "Not a punk");
            os.safeTransferFrom(address(this), msg.sender, osTokenId, 1, '');
        }
        emit BoughtPunk(msg.sender, osTokenIds);
    }

    function swapPunk(uint256[] memory ownedTokens, uint256[] memory vaultTokens) external payable whenNotPaused nonReentrant {
        require(ownedTokens.length == vaultTokens.length, "uneven swap");
        require(msg.value == min(ownedTokens.length * swapPrice, maxSwapPrice), "didnt send fee");

        //transfer owned tokens
        uint256 osTokenId;
        for(uint256 i; i < ownedTokens.length; i = uncheckedInc(i)) {
            osTokenId = ownedTokens[i];
            require(isPunk(osTokenId), "Not a punk");
            os.safeTransferFrom(msg.sender, address(this), osTokenId, 1, '');        
        }
        //transfer vault tokens
        for(uint256 i; i < vaultTokens.length; i = uncheckedInc(i)) {
            osTokenId = vaultTokens[i];
            require(isPunk(osTokenId), "Not a punk");
            os.safeTransferFrom(address(this), msg.sender, osTokenId, 1, '');
        }
        emit SwappedPunks(msg.sender, ownedTokens, vaultTokens);
    }

    function setOS(address _newOS) external onlyOwner {
        os = IERC1155(_newOS);
    }

    function setBuySellPrice(uint256 buy, uint256 sell) external onlyOwner {
        buyPrice = buy;
        salePrice = sell;
    }

    function setSwapPrice(uint256 swap, uint256 maxSwap) external onlyOwner {
        swapPrice = swap;
        maxSwapPrice = maxSwap;
    }

    function setMask(uint256 _mask) external onlyOwner {
        mask = _mask;
    }
    function setMaskedPunkValue(uint256 _maskedPunk) external onlyOwner {
        maskedPunkValue = _maskedPunk;
    }
    receive() payable external onlyOwner {
        
    }

    event BoughtPunk(address _from, uint256[] amount);
    event SoldPunk(address _from, uint256[] amount);
    event SwappedPunks(address _from, uint256[] give, uint256[] take);

    function onERC1155BatchReceived(address operator, address from, uint256[] memory ids, 
                                    uint256[] memory values, bytes memory data)  public virtual override whenNotPaused nonReentrant returns (bytes4) {
        require(operator == address(os));
        uint256 issuedRefund = ids.length * salePrice; 
        for(uint i; i < ids.length; i = uncheckedInc(i)) {
            require(isPunk(ids[i]));
        }
        if (msg.sender != owner()) {
            require(address(this).balance >= issuedRefund, "cannot accept tokens now, we're broke :(");
            payable(msg.sender).call{value: issuedRefund}('');
            emit SoldPunk(msg.sender, ids);
        }
        return this.onERC1155Received.selector;
    }
    function onERC1155Received(address operator, address from, uint256 id, 
                               uint256 value, bytes memory data) public virtual override whenNotPaused nonReentrant returns (bytes4) {
        require(operator == address(os));
        require(isPunk(id), "not a punk");
        if (msg.sender != owner()) {
            require(address(this).balance >= salePrice, "cannot accept tokens now, we're broke :(");
            payable(msg.sender).call{value: salePrice}('');
            uint256[] memory tokenArray;
            tokenArray[0] = id;
            emit SoldPunk(msg.sender, tokenArray);

        }
        return this.onERC1155Received.selector;
    }

    function uncheckedInc(uint x) pure internal returns (uint) { unchecked { return x + 1; } }
    function min(uint256 a, uint256 b) internal returns (uint256) {
        if (a < b) {
            return a;
        }
        return b;
    }

    function withdraw(uint256 amount) external onlyOwner {
        payable(msg.sender).call{value: amount}('');
    }
    function withdrawLEP(uint256 tokenId, address _to) external onlyOwner {
        os.safeTransferFrom(address(this), _to, tokenId, 1, '');
    }
}
