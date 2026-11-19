import { LightningElement, api } from 'lwc';

export default class IngredientCard extends LightningElement {
    @api name;
    @api change;
    @api direction; // 'up' or 'down'
    @api price;
    @api comment;
    @api sourceUrl = '#';
    @api sourceLabel = 'URL_REDACTED';

    get isUp() {
        return this.direction === 'up';
    }

    get badgeClass() {
        return `badge ${this.isUp ? 'badge-up' : 'badge-down'}`;
    }

    get arrowIcon() {
        return this.isUp ? '↑' : '↓';
    }
}