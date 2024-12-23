// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library MaxSkipListV2 {
    uint8 constant MAX_LEVEL = 8;

    struct Node {
        uint256 price;
        uint8 level;
        uint256[MAX_LEVEL] next;
        uint256[MAX_LEVEL] prev;
    }

    struct List {
        uint256 head;
        uint256 highestNodeId;
        uint256 length;
        uint256 nextId;
        uint256 firstFreeId;
        mapping(uint256 => Node) nodes;
        mapping(uint256 => uint256) priceToId;
    }

    event NodeInserted(uint256 indexed nodeId, uint256 price);
    event NodeRemoved(uint256 indexed nodeId, uint256 price);

    function getLevel(uint256 nodeId) internal pure returns (uint8) {
        return uint8(nodeId & 0x7);
    }

    function insert(List storage self, uint256 price) internal returns (uint256 nodeId) {
        require(price > 0, "Invalid price");
        require(self.priceToId[price] == 0, "Price exists");

        // Get nodeId
        if (self.firstFreeId != 0) {
            nodeId = self.firstFreeId;
            self.firstFreeId = self.nodes[nodeId].next[0];
        } else {
            nodeId = self.nextId;
            require(nodeId < type(uint128).max, "Too many nodes");
            self.nextId = nodeId + 1;
        }

        uint8 newLevel = getLevel(nodeId);
        
        // Update highest node if necessary
        if (self.length == 0 || price > self.nodes[self.highestNodeId].price) {
            self.highestNodeId = nodeId;
        }

        // Initialize new node
        Node storage newNode = self.nodes[nodeId];
        newNode.price = price;
        newNode.level = newLevel;

        // Clear any existing next/prev pointers
        for (uint8 i = 0; i <= newLevel; i++) {
            newNode.next[i] = 0;
            newNode.prev[i] = 0;
        }

        // Find insertion points
        uint256 current = self.head;
        uint256[MAX_LEVEL] memory updates;

        // Fixed loop: iterate from MAX_LEVEL-1 down to 0
        for (int8 i = int8(MAX_LEVEL) - 1; i >= 0; i--) {
            while (true) {
                uint256 next = self.nodes[current].next[uint8(i)];
                if (next == 0 || self.nodes[next].price < price) break;
                current = next;
            }
            updates[uint8(i)] = current;
        }

        // Insert node at each level
        for (uint8 i = 0; i <= newLevel; i++) {
            uint256 updateNode = updates[i];
            uint256 next = self.nodes[updateNode].next[i];

            // Link new node
            newNode.next[i] = next;
            newNode.prev[i] = updateNode;

            // Update next node
            if (next != 0) {
                self.nodes[next].prev[i] = nodeId;
            }

            // Update previous node
            self.nodes[updateNode].next[i] = nodeId;
        }

        self.length++;
        self.priceToId[price] = nodeId;
        emit NodeInserted(nodeId, price);
        
        return nodeId;
    }

    function remove(List storage self, uint256 price) internal returns (bool) {
        require(self.length > 0, "Empty list");
        uint256 nodeId = self.priceToId[price];
        require(nodeId != 0, "Price not found");

        Node storage node = self.nodes[nodeId];

        // If we're removing the highest node, update highestNodeId
        if (nodeId == self.highestNodeId) {
            self.highestNodeId = node.prev[0];
        }

        // Remove node from all its levels
        for (uint8 i = 0; i <= node.level; i++) {
            uint256 nextNode = node.next[i];
            uint256 prevNode = node.prev[i];

            // Update previous node's next pointer
            if (prevNode != 0) {
                self.nodes[prevNode].next[i] = nextNode;
            }

            // Update next node's prev pointer
            if (nextNode != 0) {
                self.nodes[nextNode].prev[i] = prevNode;
            }
        }

        // Add node to the free list
        node.next[0] = self.firstFreeId;
        self.firstFreeId = nodeId;

        // Clean up the price mapping and decrease length
        delete self.priceToId[price];
        self.length--;

        emit NodeRemoved(nodeId, price);
        return true;
    }

    function removeHighest(List storage self) internal returns (bool) {
        require(self.length > 0, "Empty list");

        uint256 nodeId = self.highestNodeId;
        Node storage node = self.nodes[nodeId];
        
        // Update highest pointer
        self.highestNodeId = node.prev[0];

        // Remove node from all its levels
        for (uint8 i = 0; i <= node.level; i++) {
            uint256 nextNode = node.next[i];
            uint256 prevNode = node.prev[i];
            
            if (prevNode != 0) {
                self.nodes[prevNode].next[i] = nextNode;
            }
            if (nextNode != 0) {
                self.nodes[nextNode].prev[i] = prevNode;
            }
        }

        // Add to free list
        node.next[0] = self.firstFreeId;
        self.firstFreeId = nodeId;

        // Clean up
        delete self.priceToId[node.price];
        self.length--;

        emit NodeRemoved(nodeId, node.price);
        return true;
    }

    function getHighestPrice(List storage self) internal view returns (uint256) {
        require(self.length > 0, "Empty list");
        return self.nodes[self.highestNodeId].price;
    }

    function initialize(List storage self) internal {
        require(self.head == 0, "Already initialized");
        self.head = 0;
        self.nextId = 1;
        self.firstFreeId = 0;
    }

    function exists(List storage self, uint256 price) internal view returns (bool) {
        return self.priceToId[price] != 0;
    }
}