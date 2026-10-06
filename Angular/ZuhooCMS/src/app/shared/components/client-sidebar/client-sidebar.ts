import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

interface NavItem { label: string; link: string; icon: string; }

@Component({
  selector: 'app-client-sidebar',
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './client-sidebar.html',
  styleUrl: '../sidebar/sidebar.scss',
})
export class ClientSidebar {
  // "Initialize Project" lives behind My Requests' New Request button, so it is not duplicated here.
  items: NavItem[] = [
    { label: 'Dashboard', link: '/client/dashboard', icon: 'bi-grid-1x2' },
    { label: 'Profile Settings', link: '/client/profile', icon: 'bi-person-gear' },
    { label: 'Service Catalog', link: '/client/categories', icon: 'bi-tags' },
    { label: 'My Requests', link: '/client/requests', icon: 'bi-clipboard-check' },
    { label: 'Support Tickets', link: '/client/tickets', icon: 'bi-life-preserver' },
    { label: 'My Packages', link: '/client/packages', icon: 'bi-box-seam' },
    { label: 'Payment', link: '/client/payments', icon: 'bi-credit-card' },
  ];
}
