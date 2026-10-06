package com.zuhoocms.modules.support.agent;

import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.modules.support.ticket.SupportTicketRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SupportAgentServiceImpl implements SupportAgentService {

    private final SupportAgentRepository agentRepository;
    private final UserRepository userRepository;
    private final SupportTicketRepository ticketRepository;
    private final SecurityUtil securityUtil;

    private static final Set<Role> AGENT_MANAGEMENT_ROLES =
            EnumSet.of(Role.SUPPORT_MANAGER, Role.SUPER_ADMIN, Role.SYSTEM_ADMIN);

    @Override
    @Transactional
    public SupportAgentResponse create(SupportAgentRequest request) {
        if (request.getUserId() == null) {
            throw new BadRequestException("User ID is required");
        }
        User user = userRepository.findById(request.getUserId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));
        if (!user.isRealPlatformUser()) {
            throw new BadRequestException("Only platform staff can be support agents");
        }

        if (agentRepository.findByUserId(request.getUserId()).isPresent()) {
            throw new BadRequestException("User is already a support agent");
        }

        SupportAgent agent = SupportAgent.builder()
                .user(user)
                .department(request.getDepartment())
                .specialization(request.getSpecialization())
                .status(request.getStatus() != null ? request.getStatus() : SupportAgentStatus.ACTIVE)
                .maxConcurrentTickets(request.getMaxConcurrentTickets())
                .notes(request.getNotes())
                .build();

        agent = agentRepository.save(agent);
        return SupportAgentMapper.toResponse(agent);
    }

    @Override
    @Transactional(readOnly = true)
    public SupportAgentResponse getById(Long id) {
        SupportAgent agent = agentRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));
        return SupportAgentMapper.toResponse(agent);
    }

    @Override
    @Transactional(readOnly = true)
    public SupportAgentResponse getByUserId(Long userId) {
        SupportAgent agent = agentRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));
        return SupportAgentMapper.toResponse(agent);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportAgentResponse> getAll(Pageable pageable) {
        return agentRepository.findAll(pageable)
                .map(SupportAgentMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<SupportAgentResponse> getByStatus(SupportAgentStatus status, Pageable pageable) {
        return agentRepository.findByStatus(status, pageable)
                .map(SupportAgentMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<SupportAgentResponse> getAvailableAgents() {
        return agentRepository.findByStatusAndAcceptingTicketsTrue(SupportAgentStatus.ACTIVE)
                .stream()
                .map(SupportAgentMapper::toResponse)
                .collect(Collectors.toList());
    }

    /** Notes only change when sent. */
    @Override
    @Transactional
    public SupportAgentResponse update(Long id, SupportAgentRequest request) {
        SupportAgent agent = agentRepository.lockById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));

        agent.setDepartment(request.getDepartment());
        agent.setSpecialization(request.getSpecialization());
        agent.setMaxConcurrentTickets(request.getMaxConcurrentTickets());
        if (request.getStatus() != null) {
            agent.setStatus(request.getStatus());
        }
        if (request.getNotes() != null) {
            agent.setNotes(request.getNotes());
        }

        agent = agentRepository.save(agent);
        return SupportAgentMapper.toResponse(agent);
    }

    @Override
    @Transactional
    public void updateStatus(Long id, SupportAgentStatus status) {
        SupportAgent agent = agentRepository.lockById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));
        requireSelfOrManager(agent);

        agent.setStatus(status);
        agent.setLastActiveTime(LocalDateTime.now());
        agentRepository.save(agent);
    }

    @Override
    @Transactional
    public void updateAcceptingTickets(Long id, boolean accepting) {
        SupportAgent agent = agentRepository.lockById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));
        requireSelfOrManager(agent);

        agent.setAcceptingTickets(accepting);
        agentRepository.save(agent);
    }

    /** Availability toggles belong to the agent themself, or a support manager/admin. */
    private void requireSelfOrManager(SupportAgent agent) {
        User current = securityUtil.getCurrentUser();
        if (current == null) {
            throw new ForbiddenException("Not authenticated");
        }
        boolean self = agent.getUser() != null && agent.getUser().getId().equals(current.getId());
        boolean manager = current.isPlatformUser() && AGENT_MANAGEMENT_ROLES.contains(current.getRole());
        if (!self && !manager) {
            throw new ForbiddenException("You can only change your own availability");
        }
    }

    @Override
    @Transactional
    public void updateMetrics(Long agentId) {
        SupportAgent agent = agentRepository.findById(agentId)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));

        long totalTickets = ticketRepository.countByAssignedToAgentId(agentId);
        agent.setTotalTicketsHandled((int) totalTickets);

        agentRepository.save(agent);
    }

    @Override
    @Transactional
    public SupportAgentResponse delete(Long id) {
        SupportAgent agent = agentRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Support agent not found"));

        agent.softDelete();
        agentRepository.save(agent);
        return SupportAgentMapper.toResponse(agent);
    }
}
