//SPDX-License-Identifier: NONE
pragma solidity >=0.8.9 <=0.8.19;

import "./QTypes.sol";
import "./CustomErrors.sol";

library LinkedList {

  struct OrderbookSide {
    uint64 head;
    uint64 tail;
    uint64 idCounter;
    uint64 length;
    mapping(uint64 => QTypes.Quote) quotes;
  }

    
  /// @notice Get the `Quote` with id `id`
  function get(OrderbookSide storage self, uint64 id) internal view returns(QTypes.Quote memory){
    QTypes.Quote memory quote = self.quotes[id];
    return quote;
  }
    
  /// @notice Insert a new `Quote` as the new head of the linked list
  /// @return uint64 Id of the new `Quote`
  function addHead(
                   OrderbookSide storage self,
                   address quoter,
                   uint8 quoteType,
                   uint64 APR,
                   uint cashflow                    
                   ) internal returns(uint64){

    // Create a new unlinked object representing the new head
    QTypes.Quote memory newQuote = createQuote(self, quoter, quoteType, APR, cashflow);

    // Link `newQuote` before the current head
    link(self, newQuote.id, self.head);

    // Set the head pointer to `newQuote`
    setHeadId(self, newQuote.id);

    if(self.tail == 0) {
      // `OrderbookSide` is currently empty, so set tail = head
      setTailId(self, newQuote.id);
    }

    return newQuote.id;
  }

  /// @notice Insert a new `Quote` as the tail of the linked list
  /// @return uint64 Id of the new `Quote`
  function addTail(
                   OrderbookSide storage self,
                   address quoter,
                   uint8 quoteType,
                   uint64 APR,
                   uint cashflow
                   ) internal returns(uint64) {
    
    if (self.head == 0) {

      // `OrderbookSide` is currently empty, so set head = tail
      return addHead(self, quoter, quoteType, APR, cashflow);

    } else {

      // Create a new unlinked object representing the new tail
      QTypes.Quote memory newQuote = createQuote(self, quoter, quoteType, APR, cashflow);

      // Link `newQuote` after the current tail
      link(self, self.tail, newQuote.id);

      // Set the tail pointer to `newQuote`
      setTailId(self, newQuote.id);

      return newQuote.id;
    }    
  }


  /// @notice Remove the `Quote` with id `id` from the linked list
  function remove(OrderbookSide storage self, uint64 id) internal {
    if (self.quotes[id].id != id) {
      revert CustomErrors.LL_Quote_Not_Exist();
    }
    
    QTypes.Quote memory quoteToRemove = self.quotes[id];

    if(self.head == id && self.tail == id) {
      // `OrderbookSide` only has one element. Reset both head and tail pointers
      setHeadId(self, 0);
      setTailId(self, 0);
    } else if (self.head == id) {
      // `quoteToRemove` is the current head, so set the next item in the linked list to be head
      setHeadId(self, quoteToRemove.next);
      self.quotes[quoteToRemove.next].prev = 0;
    } else if (self.tail == id) {
      // `quoteToRemove` is the current tail, so set the prev item in the linked list to be tail
      setTailId(self, quoteToRemove.prev);
      self.quotes[quoteToRemove.prev].next = 0;
    } else {
      // Link the `Quote`s before and after `quoteToRemove` together
      link(self, quoteToRemove.prev, quoteToRemove.next);
    }

    // Ready to delete `quoteToRemove`
    delete self.quotes[quoteToRemove.id];

    // Decrement the length of the `OrderbookSide`
    self.length--;
  }
  
  /// @notice Insert a new `Quote` after the `Quote` with id `prev`
  /// @return uint64 Id of the new `Quote`
  function insertAfter(
                       OrderbookSide storage self,
                       uint64 prev,
                       address quoter,
                       uint8 quoteType,
                       uint64 APR,
                       uint cashflow
                       ) internal returns(uint64){
    
    if(prev == self.tail) {     

      // Prev element is the tail, make this `Quote` the new tail
      return addTail(self, quoter, quoteType, APR, cashflow);
            
    } else {

      // Create a new unlinked object representing the new `Quote`
      QTypes.Quote memory newQuote = createQuote(self, quoter, quoteType, APR, cashflow);

      // Get the `Quote`s before and after `newQuote`
      QTypes.Quote memory prevQuote = self.quotes[prev];      
      QTypes.Quote memory nextQuote = self.quotes[prevQuote.next];

      // Insert the new `Quote` between `prevQuote` and `nextQuote`
      link(self, newQuote.id, nextQuote.id);
      link(self, prevQuote.id, newQuote.id);

      return newQuote.id;
    }    
  }

  /// @notice Insert a new `Quote` before the `Quote` with id `next`
  /// @return uint64 Id of the new `Quote`
  function insertBefore(
                        OrderbookSide storage self,
                        uint64 next,
                        address quoter,
                        uint8 quoteType,
                        uint64 APR,
                        uint cashflow
                        ) internal returns(uint64){

    if(next == self.head) {

      // Next element is the head, make this `Quote` the new head
      return addHead(self, quoter, quoteType, APR, cashflow);
      
    } else {

      // inserting before `next` is equivalent to inserting after `next.prev`
      return insertAfter(self, self.quotes[next].prev, quoter, quoteType, APR, cashflow);
      
    }
    
  }
                        
  /// @notice Update the pointer to head of the linked list
  function setHeadId(OrderbookSide storage self, uint64 head) internal {
    self.head = head;
  }

  /// @notice Update the pointer to tail of the linked list
  function setTailId(OrderbookSide storage self, uint64 tail) internal {
    self.tail = tail;
  }
  
  /// @notice Create a new unlinked `Quote`
  function createQuote(
                       OrderbookSide storage self,
                       address quoter,
                       uint8 quoteType,
                       uint64 APR,
                       uint cashflow
                       ) internal returns(QTypes.Quote memory) {

    // Increment the counter for new id's.
    // Note this means non-empty linked lists start with id = 1
    self.idCounter = self.idCounter + 1;    
    
    // Create a new unlinked `Quote` with the latest `idCounter`
    QTypes.Quote memory newQuote = QTypes.Quote(self.idCounter, 0, 0, quoter, quoteType, APR, cashflow, 0);
    
    // Add the `Quote` to the internal mapping of `Quote`s
    self.quotes[newQuote.id] = newQuote;
    
    // Increment the length of the `OrderbookSide`
    self.length++;
    
    return newQuote;
  }

  /// @notice Link two `Quote`s together
  function link(
                OrderbookSide storage self,
                uint64 prev,
                uint64 next
                ) internal {
    
    self.quotes[prev].next = next;
    self.quotes[next].prev = prev;
    
  }
  
}

