# Salesforce E-Commerce AI Assistant (Clothing Store)

An intelligent e-commerce assistant built on **Salesforce** using **Agentforce AI**, **Lightning Web Components (LWC)**, **Apex**, and **SOQL**. This application helps customers check clothing availability in real time, track their orders, and calculate shipping costs through a custom conversational chat widget.

---

## Features
* **AI Shopping Assistant (Agentforce):** Guides customers through available clothing items, sizes, and product details[cite: 5].
* **Order & Shipment Tracking:** Allows clients to check their order status and calculate shipping costs dynamically[cite: 5].
* **Custom Agent Chat Widget (LWC):** Interactive frontend chat component (`agentChatWidget`) built with HTML, CSS, JavaScript, and XML metadata configuration, connected directly to backend Apex controllers.

---

## Tech Stack
* **Frontend:** Lightning Web Components (`agentChatWidget` — HTML5, CSS3, Modern JavaScript, XML)
* **Backend:** Apex, SOQL
* **AI & Platform:** Salesforce Agentforce, Salesforce DX

---

## Key Project Structure
* `force-app/main/default/lwc/agentChatWidget/` — Frontend Lightning Web Component containing:
  * `agentChatWidget.html` (Chat UI structure)
  * `agentChatWidget.css` (Custom chat styling)
  * `agentChatWidget.js` (Client-side logic & Apex integration)
  * `agentChatWidget.js-meta.xml` (Component visibility & target configuration)
* `force-app/main/default/classes/` — Backend Apex controllers (`AgentChatController.cls`, `chat_interface.cls`) handling Agentforce API communication and SOQL queries[cite: 4].

---

## Setup & Configuration
1. Clone the repository:
   ```bash
   git clone [https://github.com/moemench3/sales-force-E-Commerce-Assistant-in-cloth-shop.git](https://github.com/moemench3/sales-force-E-Commerce-Assistant-in-cloth-shop.git)
