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

---

## Additional Project: Recipe Optimizer & AI Recipe Copilot (Salesforce)

An interactive Salesforce application designed to manage products, formulate and optimize ingredient recipes, track ingredient market prices and price projections, and generate tailored product recipes using **Agentforce Copilot**.

### Key Features
* **Product Catalog & Recipe Builder (`recipeOptimizer`, `ingrediant`, `ingredientCard`):** Create products, add or create ingredients, adjust weights/percentages, and manage recipe items.
* **Recipe Optimization & Cost Impact (`IngredientOptimizationController.cls`, `RecipeOptimizerController.cls`):** Optimize ingredient distribution and compare current cost against AI-optimized results[cite: 9].
* **Market Intelligence & Price Projections (`CommodityMarketScoutController.cls`, `RecipePriceProjectionAction.cls`):** Scout market pricing, inspect price history/trends, and project recipe costs[cite: 9].
* **Agentforce Copilot & Loading UX (`ingredientAiService.js`, `mockIngredientData.js`, `aiAgentSpinner`):** Generate custom recipes and display AI processing states smoothly[cite: 10].

### Components & Classes Included
* **Apex Controllers & Actions (`force-app/main/default/classes/`):**
  * `CommodityMarketScoutController.cls`[cite: 9]
  * `IngredientOptimizationController.cls`[cite: 9]
  * `RecipeOptimizerController.cls`[cite: 9]
  * `RecipePriceProjectionAction.cls`[cite: 9]
* **LWC Modules (`force-app/main/default/lwc/`):**
  * `aiAgentSpinner` (`aiAgentSpinner.html`, `aiAgentSpinner.js`, `aiAgentSpinner.css`, `aiAgentSpinner.js-meta.xml`)[cite: 10]
  * `ingrediant` (`ingrediant.html`, `ingrediant.js`, `ingrediant.css`, `ingrediant.js-meta.xml`, plus `__tests__`)[cite: 10]
  * `ingredientCard` (`ingredientCard.html`, `ingredientCard.js`, `ingredientCard.css`, `ingredientCard.js-meta.xml`, plus `__tests__`)[cite: 10]
  * `recipeOptimizer` (`recipeOptimizer.html`, `recipeOptimizer.js`, `recipeOptimizer.css`, `recipeOptimizer.js-meta.xml`, `ingredientAiService.js`, `mockIngredientData.js`)[cite: 10]

### Additional Frontend & Build Files Included
* **HTML, CSS, JavaScript & Webpack:** Frontend web files and bundling configuration included within the repository alongside the Salesforce metadata.
